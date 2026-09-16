variable "namespaces" {
  description = <<-EOT
    The namespaces to ensure exist, by full name. REQUIRED, no default: which
    namespaces a deployment runs in is a fact the consumer derives from what it
    deploys — the module does not know it. Whatever applies workloads to the
    cluster afterwards assumes these are present and does NOT create them.
    Each name is a DNS-1123 label.
  EOT
  type        = set(string)

  validation {
    condition     = length(var.namespaces) >= 1
    error_message = "At least one namespace is required."
  }

  validation {
    condition     = alltrue([for ns in var.namespaces : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", ns))])
    error_message = "Each namespace must be a DNS-1123 label (1-63 lowercase alphanumerics or hyphens, starting and ending alphanumeric)."
  }
}

variable "labels" {
  description = "Optional per-namespace labels, keyed by namespace name. A namespace absent from this map gets no extra labels."
  type        = map(map(string))
  default     = {}
}
