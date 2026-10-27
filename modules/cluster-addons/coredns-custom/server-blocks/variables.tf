variable "zones" {
  description = "DNS zones whose queries CoreDNS forwards to the forwarder."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for z in var.zones :
      can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", z))
    ])
    error_message = "Each zone must be a lowercase DNS name of two or more labels (letters, digits, hyphens), without a trailing dot, e.g. privatelink.vaultcore.azure.net."
  }

  # These would override the kubernetes plugin's own zones and break in-cluster DNS.
  validation {
    condition = alltrue([
      for z in var.zones :
      !anytrue([for r in ["cluster.local", "in-addr.arpa", "ip6.arpa"] : z == r || endswith(z, ".${r}")])
    ])
    error_message = "zones must not include cluster.local, in-addr.arpa or ip6.arpa, or a subdomain of them: they would override CoreDNS's own cluster and reverse zones."
  }

  validation {
    condition     = length(distinct(var.zones)) == length(var.zones)
    error_message = "zones must not repeat a zone: CoreDNS refuses two server blocks for the same zone."
  }
}

variable "forwarder" {
  description = "Resolver the zones are forwarded to. The default is Azure DNS (168.63.129.16), reachable from every node of a VNet and aware of the private DNS zones linked to it."
  type        = string
  default     = "168.63.129.16"

  validation {
    condition     = can(regex("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$", var.forwarder))
    error_message = "forwarder must be an IPv4 address."
  }
}
