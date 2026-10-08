# Pure mapping (no provider, no resources): boundary -> one store per (boundary, namespace). Kept
# apart from the add-on so the isolation rules are testable without a provider on Terraform 1.6
# and OpenTofu.
output "boundaries" {
  description = "Per boundary: its vault and namespaces."
  value = { for k, s in var.secret_stores : k => {
    key_vault_id = s.key_vault_id
    vault_uri    = s.vault_uri
    namespaces   = s.namespaces
  } }
}

output "stores" {
  description = "One entry per (boundary, namespace), keyed \"<boundary>/<namespace>\"."
  value = merge([for k, s in var.secret_stores : {
    for ns in s.namespaces : "${k}/${ns}" => {
      boundary   = k
      namespace  = ns
      vault_uri  = s.vault_uri
      federation = "${k}-${ns}"
    }
  }]...)
}
