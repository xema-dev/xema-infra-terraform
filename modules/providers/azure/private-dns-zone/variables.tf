variable "private_cluster_enabled" {
  description = "Whether the cluster's API is private (providers/azure/cluster's private_cluster_enabled)."
  type        = bool
  default     = false
}

variable "public_fqdn_enabled" {
  description = "Whether the private API address is also published under a public DNS name (providers/azure/cluster's private_cluster_public_fqdn_enabled)."
  type        = bool
  default     = false
}

variable "private_dns_zone_id" {
  description = "The API's private DNS zone: null (AKS default, \"System\"), \"System\", \"None\" or the resource id of an Azure private DNS zone."
  type        = string
  default     = null

  validation {
    condition = var.private_dns_zone_id == null || contains(["System", "None"], coalesce(var.private_dns_zone_id, "-")) || can(regex(
      "(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/[^/]+$", coalesce(var.private_dns_zone_id, "-")
    ))
    error_message = "private_dns_zone_id must be null, \"System\", \"None\" or the resource id of an Azure private DNS zone (/subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/<zone>)."
  }
}
