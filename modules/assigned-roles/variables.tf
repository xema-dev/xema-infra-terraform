variable "enable_cluster" {
  description = "The caller enables providers/azure/cluster (Network Contributor)."
  type        = bool
  default     = false
}

variable "enable_container_registry" {
  description = "The caller enables providers/azure/container-registry (AcrPull)."
  type        = bool
  default     = false
}

variable "enable_dns" {
  description = "The caller enables providers/azure/dns (DNS Zone Contributor)."
  type        = bool
  default     = false
}

variable "enable_secrets_backend" {
  description = "The caller enables providers/azure/secrets-backend (Key Vault Secrets Officer and User)."
  type        = bool
  default     = false
}
