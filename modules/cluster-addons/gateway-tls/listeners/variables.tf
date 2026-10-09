variable "listeners" {
  description = <<-EOT
    The Gateway's HTTPS listeners, keyed by listener name (the HTTPRoute parentRef sectionName).
    One listener per hostname, each with its own certificate. Each entry:
      - hostname         : the host it serves, exact ("app.example.com") or a wildcard
                           ("*.example.com"); any number of apex domains may appear
      - certificate_mode : "managed" (cert-manager issues the certificate from the ACME
                           ClusterIssuer into a Secret the module names) or
                           "customer_supplied" (the customer provides a kubernetes.io/tls
                           Secret in the Gateway's namespace; the module issues nothing)
      - secret_name      : the customer's Secret, required with customer_supplied and
                           refused with managed (the module names that Secret itself)
  EOT
  type = map(object({
    hostname         = string
    certificate_mode = string
    secret_name      = optional(string)
  }))

  validation {
    condition     = alltrue([for k, _ in var.listeners : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", k)) && k != "http"])
    error_message = "Each listener key must be a DNS-1123 label (1-63 lowercase letters, digits or hyphens, starting and ending alphanumeric) other than \"http\", which is the port-80 listener's name."
  }

  validation {
    condition     = length(var.listeners) <= 63
    error_message = "At most 63 HTTPS listeners: a Gateway holds 64 listeners and one is the port-80 listener."
  }

  validation {
    condition     = alltrue([for _, l in var.listeners : length(l.hostname) <= 253 && can(regex("^(\\*\\.)?[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)+$", l.hostname))])
    error_message = "Each listener hostname must be a lowercase DNS name with at least two labels, optionally prefixed by \"*.\" (a wildcard), at most 253 characters."
  }

  validation {
    condition     = length([for _, l in var.listeners : l.hostname]) == length(distinct([for _, l in var.listeners : l.hostname]))
    error_message = "Each hostname may appear on only one listener: two HTTPS listeners on one port with the same hostname conflict, and the Gateway serves neither."
  }

  validation {
    condition     = alltrue([for _, l in var.listeners : contains(["managed", "customer_supplied"], l.certificate_mode)])
    error_message = "Each listener certificate_mode must be one of managed, customer_supplied."
  }

  validation {
    condition     = alltrue([for _, l in var.listeners : l.certificate_mode != "customer_supplied" || (can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", l.secret_name)) && try(length(l.secret_name) <= 253, false))])
    error_message = "A customer_supplied listener requires secret_name: the DNS-1123 subdomain name of the customer's kubernetes.io/tls Secret in the Gateway's namespace."
  }

  validation {
    condition     = alltrue([for _, l in var.listeners : l.certificate_mode != "managed" || l.secret_name == null])
    error_message = "A managed listener takes no secret_name: the module names the Secret cert-manager issues into (\"<gateway_name>-<listener>-tls\")."
  }
}

variable "gateway_name" {
  description = "Name of the Gateway; prefixes each managed listener's Certificate and Secret."
  type        = string
}

variable "cluster_issuer_name" {
  description = "The ACME ClusterIssuer every managed listener's Certificate references."
  type        = string
}

variable "tls_solver" {
  description = "The ClusterIssuer's ACME solver (\"http01\" | \"dns01-azure\"); decides which managed hostnames can be issued."
  type        = string

  validation {
    condition     = contains(["http01", "dns01-azure"], var.tls_solver)
    error_message = "tls_solver must be one of http01, dns01-azure."
  }
}

variable "dns01_zones" {
  description = "With dns01-azure, the DNS zones the solver writes challenge records into (one per apex it issues for); every managed hostname must sit in one of them. Empty with http01."
  type        = set(string)
  default     = []
}
