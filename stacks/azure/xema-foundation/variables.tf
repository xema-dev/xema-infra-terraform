variable "azure_subscription_id" {
  description = "Azure subscription the deployment lives in. Empty uses the provider's ambient subscription (ARM_SUBSCRIPTION_ID / az login)."
  type        = string
  default     = ""
}

variable "deployment_name" {
  description = "Deployment name — the SAME value the substrate stack is given. Every name here derives from it."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.deployment_name))
    error_message = "deployment_name must be lower-case letters, digits and hyphens, 3-32 characters, starting with a letter."
  }
}

variable "region" {
  description = "Azure region of the deployment (every resource of the deployment lives in one region)."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space of the deployment's virtual network."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_prefix" {
  description = "AKS node subnet."
  type        = string
  default     = "10.0.0.0/20"
}

variable "postgres_subnet_prefix" {
  description = "Subnet delegated to PostgreSQL Flexible Server."
  type        = string
  default     = "10.0.16.0/24"
}

variable "private_endpoint_subnet_prefix" {
  description = "Subnet for the private endpoints of the cache, storage account and key vault."
  type        = string
  default     = "10.0.17.0/24"
}

variable "management_subnet_prefix" {
  description = "Subnet of the management runner."
  type        = string
  default     = "10.0.18.0/28"
}

variable "private_link_services" {
  description = "Backing services reached through private endpoints — one private DNS zone each. Must cover every service the substrate makes private (backing_services_network_access = \"private\"). Closed set: blob, redis, vault."
  type        = list(string)
  default     = ["blob", "redis", "vault"]
}

variable "management_runner" {
  description = <<-EOT
    The management runner: one small VM inside the network, from which the
    substrate stack and the deployment engine run, and through which a human
    reaches the private services over SSH. null = no runner (only when every
    backing service is public and the PostgreSQL server is public too).
      - ssh_public_keys   : required, non-empty — password login is disabled
      - allowed_ssh_cidrs : required, non-empty — the whole internet is refused
      - vm_size           : optional, default Standard_B2als_v2
  EOT
  type = object({
    ssh_public_keys   = list(string)
    allowed_ssh_cidrs = list(string)
    vm_size           = optional(string, "Standard_B2als_v2")
  })
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}
