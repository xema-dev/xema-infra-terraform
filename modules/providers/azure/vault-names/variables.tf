variable "deployment_name" {
  description = "The stack's name prefix; every derived vault name starts with it."
  type        = string
}

variable "operator_vault_name" {
  description = "Explicit name for the operator vault. Empty derives \"<deployment_name>-kv\"."
  type        = string
  default     = ""
}

variable "boundaries" {
  description = "One entry per secret trust boundary, keyed by boundary name. vault_name is an explicit vault name; empty derives \"<deployment_name>-<boundary>-kv\"."
  type = map(object({
    vault_name = optional(string, "")
  }))
  default = {}
}
