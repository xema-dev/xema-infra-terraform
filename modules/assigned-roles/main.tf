# No providers, no resources, no data sources: the answer is a function of the flags alone, so a
# bootstrap can call this before any state (or any cloud credential) exists.
#
# `by_module` is checked against the code, not trusted: tooling/check-assigned-roles.mjs (and
# tests/assigned_roles.tftest.hcl for the shape) fail CI when a `role_definition_name` used
# anywhere in modules/ or stacks/ is missing here, or a module's own `assigned_role_names` output
# differs from its entry. The keys are the module directory names under modules/providers/azure/.
locals {
  by_module = {
    "cluster"            = ["Network Contributor"]
    "container-registry" = ["AcrPull"]
    "dns"                = ["DNS Zone Contributor"]
    "secrets-backend"    = ["Key Vault Secrets Officer", "Key Vault Secrets User"]
  }

  enabled = {
    "cluster"            = var.enable_cluster
    "container-registry" = var.enable_container_registry
    "dns"                = var.enable_dns
    "secrets-backend"    = var.enable_secrets_backend
  }
}
