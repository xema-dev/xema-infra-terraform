variable "name" {
  description = "Name prefix of the endpoint and its service connection."
  type        = string
}

variable "region" {
  description = "Azure region (must be the VNet's)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the endpoint in."
  type        = string
}

variable "service" {
  description = "Which private-link service the endpoint reaches. Closed set: blob, redis, vault."
  type        = string

  validation {
    condition     = contains(["blob", "redis", "vault"], var.service)
    error_message = "service must be one of blob, redis, vault."
  }
}

variable "target_resource_id" {
  description = "Resource id of the storage account, cache or key vault."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the endpoint's NIC is placed in (providers/azure/network's private_endpoint_subnet_id)."
  type        = string
}

variable "private_dns_zone_id" {
  description = "Private DNS zone of this service, linked to the VNet (providers/azure/network's private_dns_zone_ids[service])."
  type        = string
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}
