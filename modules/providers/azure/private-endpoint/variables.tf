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
  description = "Which private-link service the endpoint reaches. Closed set: blob, redis, vault, postgres."
  type        = string

  validation {
    condition     = contains(["blob", "redis", "vault", "postgres"], var.service)
    error_message = "service must be one of blob, redis, vault, postgres."
  }
}

variable "target_resource_id" {
  description = "Resource id of the storage account, cache, key vault or PostgreSQL flexible server."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the endpoint's NIC is placed in (providers/azure/network's private_endpoint_subnet_id)."
  type        = string
}

variable "private_dns_zone_id" {
  description = "Private DNS zone to register the endpoint's record in (providers/azure/network's private_dns_zone_ids[service], or a zone the network's owner runs). Required when register_dns_record = true."
  type        = string
  default     = ""
}

variable "register_dns_record" {
  description = "Register the endpoint's A record in private_dns_zone_id (default true). false leaves registration to the network's owner — e.g. a landing zone whose policy registers private endpoints in its central zones."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}
