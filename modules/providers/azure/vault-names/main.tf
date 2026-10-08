# Pure naming (no provider, no resources): the Key Vault names of the operator vault and of each
# secret trust boundary. A derived name that would not be a valid vault name is REFUSED, never
# truncated: a truncated name can collide with another boundary's. The caller sets an explicit
# name for that entry instead. Kept apart from the stack so the rules are testable without a
# provider on Terraform 1.6 and OpenTofu.
locals {
  operator_name = var.operator_vault_name != "" ? var.operator_vault_name : "${var.deployment_name}-kv"
  boundary_names = { for k, b in var.boundaries :
    k => b.vault_name != "" ? b.vault_name : "${var.deployment_name}-${k}-kv"
  }

  all_names = merge({ "(operator)" = local.operator_name }, local.boundary_names)

  # Azure: 3-24 letters, digits and single hyphens, starting with a letter, ending alphanumeric.
  invalid = [for k, n in local.all_names : k if !(can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", n)) && !can(regex("--", n)))]
  lowered = [for _, n in local.all_names : lower(n)]
}

resource "terraform_data" "guard" {
  lifecycle {
    precondition {
      condition     = length(local.invalid) == 0
      error_message = "Key Vault names must be 3-24 letters, digits or single hyphens, starting with a letter and ending alphanumeric. Invalid for: ${join(", ", local.invalid)}. A derived name is never truncated: set the operator vault name, or the boundary's vault_name, explicitly."
    }
    precondition {
      condition     = length(local.lowered) == length(distinct(local.lowered))
      error_message = "Every Key Vault name must be distinct (case-insensitively): a boundary may not share a vault with another boundary or with the operator vault."
    }
  }
}

output "operator" {
  description = "Name of the operator vault."
  value       = local.operator_name
}

output "boundaries" {
  description = "Vault name per boundary key."
  value       = local.boundary_names
}
