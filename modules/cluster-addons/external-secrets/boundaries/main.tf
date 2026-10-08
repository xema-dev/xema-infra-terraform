# Pure mapping and guards (no provider): boundary -> one store, with its own managed identity, per
# (boundary, namespace). Kept apart from the add-on so the isolation and naming rules are testable
# without a provider (or a mock) on Terraform 1.6 and OpenTofu.
locals {
  stores = merge([for k, s in var.secret_stores : {
    for ns in s.namespaces : "${k}/${ns}" => {
      boundary      = k
      namespace     = ns
      vault_uri     = s.vault_uri
      key_vault_id  = s.key_vault_id
      identity_name = "${var.identity_name_prefix}-${k}-${ns}"
    }
  }]...)

  # Azure user-assigned managed identity: 3-128 of letters, digits, hyphens and underscores,
  # starting with a letter or digit.
  invalid_identity_names = [for _, st in local.stores : st.identity_name if !can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{2,127}$", st.identity_name))]

  unknown_namespaces = var.known_namespaces == null ? [] : sort(distinct([for _, st in local.stores : st.namespace if !contains(var.known_namespaces, st.namespace)]))
}

resource "terraform_data" "guard" {
  lifecycle {
    precondition {
      condition     = length(local.invalid_identity_names) == 0
      error_message = "Managed identity names must be 3-128 letters, digits, hyphens or underscores, starting alphanumeric. Too long or invalid: ${join(", ", local.invalid_identity_names)}. A name is never truncated: shorten the identity name prefix, the boundary name or the namespace name."
    }
    precondition {
      condition     = length(local.unknown_namespaces) == 0
      error_message = "Every boundary namespace must be one the stack creates (workload_namespaces): a SecretStore is installed into it without creating it, so on a fresh cluster it would not exist. Not in the roster: ${join(", ", local.unknown_namespaces)}."
    }
  }
}

output "boundaries" {
  description = "Per boundary: its vault and namespaces."
  value = { for k, s in var.secret_stores : k => {
    key_vault_id = s.key_vault_id
    vault_uri    = s.vault_uri
    namespaces   = s.namespaces
  } }
}

output "stores" {
  description = "One entry per (boundary, namespace), keyed \"<boundary>/<namespace>\"; each has its own managed identity name."
  value       = local.stores

  depends_on = [terraform_data.guard]
}
