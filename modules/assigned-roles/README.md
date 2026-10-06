# assigned-roles

Returns `assigned_role_names`: the Azure role definition names the stack assigns, as a static,
sorted, de-duplicated list for the set of modules the caller enables. No providers, no resources,
no data sources, so a bootstrap can call it before any state or cloud credential exists.

```hcl
module "assigned_roles" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/assigned-roles?ref=v0.12.1"

  enable_cluster            = true
  enable_container_registry = true
  enable_dns                = true
  enable_secrets_backend    = true
}
```

Inputs: `enable_cluster`, `enable_container_registry`, `enable_dns`, `enable_secrets_backend`
(bool, default `false`), mirroring the stack's `enable_*` flags. The result is a superset of what
one apply creates (a module lists every role it can assign, whatever its inputs), which is what an
allow-list needs.

## Deriving the RBAC-Administrator ABAC condition

The identity that applies the stack holds Role Based Access Control Administrator, constrained to
assigning only these roles. Build the condition from the list instead of copying role names by hand:

```hcl
data "azurerm_role_definition" "assignable" {
  for_each = toset(module.assigned_roles.assigned_role_names)
  name     = each.value
  scope    = "/subscriptions/${var.subscription_id}"
}

locals {
  role_guids = [for d in data.azurerm_role_definition.assignable : trimprefix(d.id, "${d.scope}/providers/Microsoft.Authorization/roleDefinitions/")]
  guid_list  = join(", ", local.role_guids)

  # Constrain both the write (create) and the delete of a role assignment to the listed roles.
  rbac_condition = <<-EOT
    ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR
      (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId]
        ForAnyOfAnyValues:GuidEquals {${local.guid_list}}))
    AND
    ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR
      (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId]
        ForAnyOfAnyValues:GuidEquals {${local.guid_list}}))
  EOT
}

resource "azurerm_role_assignment" "applier_rbac_admin" {
  scope                              = "/subscriptions/${var.subscription_id}"
  role_definition_name               = "Role Based Access Control Administrator"
  principal_id                       = var.applier_principal_id
  condition_version                  = "2.0"
  condition                          = local.rbac_condition
}
```

(`principal_type = "ServicePrincipal"` is set on every assignment the modules create, so the
condition can evaluate the request.) Adding a module that assigns a new role changes the list on
the next release; the bootstrap picks it up by bumping `?ref=`, with nothing to copy.

## Kept honest

Each module that creates `azurerm_role_assignment` exposes `assigned_role_names` (a literal list).
`tooling/check-assigned-roles.mjs` (CI, and `node --test tooling/check-assigned-roles.test.mjs`)
fails when a `role_definition_name` anywhere under `modules/` or `stacks/` is missing from this
module, when a module's output disagrees with its code, or when a name is not a plain literal.
`tests/assigned_roles.tftest.hcl` (`tofu test`) pins the list's shape: sorted, de-duplicated, only
enabled modules.
