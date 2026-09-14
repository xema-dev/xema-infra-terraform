variable "domain" {
  description = "Managed zone apex (e.g. \"example.com\")."
  type        = string
}

variable "records" {
  description = <<-EOT
    DNS records keyed by a stable id. Each record:
      - name  : record name relative to the zone apex ("@" for the apex; "*" and
                "*.sub" wildcards are supported)
      - type  : one of "A", "AAAA", "CNAME", "TXT"; default "A"
      - value : record value. CNAME values are stored verbatim (Azure accepts
                either "target.example.com" or "target.example.com.").
      - ttl   : time-to-live in seconds; default 300
  EOT
  type = map(object({
    name  = string
    type  = optional(string, "A")
    value = string
    ttl   = optional(number, 300)
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in values(var.records) : contains(["A", "AAAA", "CNAME", "TXT"], r.type)
    ])
    error_message = "record type must be one of A, AAAA, CNAME, TXT."
  }
}

variable "region" {
  description = "Azure location for the resources that need one — the created resource group (when resource_group_name is empty) and the DNS-01 identity (when enabled). The zone itself is global. Required exactly when either of those is created; a precondition says so."
  type        = string
  default     = ""
}

variable "resource_group_name" {
  description = "Existing resource group to create the zone in. Empty string creates a dedicated resource group named \"<domain with dots replaced by hyphens>-dns-rg\"."
  type        = string
  default     = ""
}

variable "dns01_workload_identity" {
  description = <<-EOT
    Optionally mint a user-assigned identity that may edit THIS zone (DNS Zone
    Contributor) and federate it to a Kubernetes service account through the
    cluster's OIDC issuer — what cert-manager's ACME DNS-01 azureDNS solver uses
    with workload identity (see cluster-addons/ingress-tls).
      - enabled                   : create the identity + federated credential
      - oidc_issuer_url           : the cluster's OIDC issuer (providers/azure/cluster output)
      - service_account_namespace : namespace of the solver's service account (default "cert-manager")
      - service_account_name      : name of the solver's service account (default "cert-manager")
  EOT
  type = object({
    enabled                   = bool
    oidc_issuer_url           = string
    service_account_namespace = optional(string, "cert-manager")
    service_account_name      = optional(string, "cert-manager")
  })
  default = {
    enabled         = false
    oidc_issuer_url = ""
  }

  validation {
    condition     = !var.dns01_workload_identity.enabled || startswith(var.dns01_workload_identity.oidc_issuer_url, "https://")
    error_message = "dns01_workload_identity.oidc_issuer_url must be an https:// URL when enabled."
  }
}

variable "tags" {
  description = "Tags applied to every created resource."
  type        = map(string)
  default     = {}
}
