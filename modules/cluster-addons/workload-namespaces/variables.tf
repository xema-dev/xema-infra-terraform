variable "namespaces" {
  description = <<-EOT
    The namespaces that must exist before the Helm application bring-up runs. The
    bring-up assumes these are present and does NOT create them. Defaults to the
    canonical Xema set; override to adopt the module for a different deployment.
  EOT
  type        = set(string)
  default = [
    "xema-prod",
    "shared-prod",
    "xema-infra",
    "xema-opencode-workers",
    "xema-biome-sidecars",
    "xema-biome-apis",
    "xema-image-builders",
  ]

  validation {
    condition     = length(var.namespaces) >= 1
    error_message = "At least one namespace is required."
  }
}

variable "labels" {
  description = "Optional per-namespace labels, keyed by namespace name. A namespace absent from this map gets no extra labels."
  type        = map(map(string))
  default     = {}
}
