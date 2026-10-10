# assigned-roles

Returns `assigned_role_names`: the Azure role definition names the stack assigns, as a sorted, de-duplicated list for the modules you enable. It has no providers, resources or data sources, so a bootstrap can call it before any state or cloud credential exists.

## When to use it

Use it to build the allow-list for the Role Based Access Control Administrator condition of the identity that applies the stack, instead of copying role names by hand. The list is a superset of what one apply creates.

## Usage

```hcl
module "assigned_roles" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/assigned-roles?ref=v0.13.0"

  enable_cluster            = true
  enable_container_registry = true
  enable_dns                = true
  enable_secrets_backend    = true
}

data "azurerm_role_definition" "assignable" {
  for_each = toset(module.assigned_roles.assigned_role_names)
  name     = each.value
  scope    = "/subscriptions/${var.subscription_id}"
}
```

Use the resulting role GUIDs in the `condition` of the applier's `azurerm_role_assignment`, constraining both `roleAssignments/write` and `roleAssignments/delete`.

`tooling/check-assigned-roles.mjs` (run in CI) fails when a `role_definition_name` under `modules/` or `stacks/` is missing from this module.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `enable_cluster` | no | The caller enables providers/azure/cluster (Network Contributor). |
| `enable_container_registry` | no | The caller enables providers/azure/container-registry (AcrPull). |
| `enable_dns` | no | The caller enables providers/azure/dns (DNS Zone Contributor). |
| `enable_secrets_backend` | no | The caller enables providers/azure/secrets-backend (Key Vault Secrets Officer and User). |

Outputs: `assigned_role_names`.
