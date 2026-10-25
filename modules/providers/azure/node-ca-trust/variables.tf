variable "certificates" {
  description = "PEM CA certificates added to every node's trust store (providers/azure/cluster's custom_ca_trust_certificates)."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.certificates) <= 10
    error_message = "custom_ca_trust_certificates holds at most 10 certificates (an AKS limit)."
  }

  validation {
    condition = alltrue([
      for c in var.certificates :
      can(regex("^-----BEGIN CERTIFICATE-----\n[A-Za-z0-9+/=\n]+\n-----END CERTIFICATE-----$", trimspace(c)))
    ])
    error_message = "Each custom_ca_trust_certificates entry must be exactly ONE PEM certificate (-----BEGIN CERTIFICATE----- ... -----END CERTIFICATE-----), LF line endings, no other text. Put each certificate in its own entry."
  }

  # AKS documents the 35 KB limit on the CERTIFICATE CONTENT (the PEM file the CLI
  # takes: certificates separated by a blank line), not on the base64 API field,
  # which the API spec limits only by count (maxItems 10). Measured here as that
  # file — trimmed PEMs joined by "\n\n" — against 35000 bytes, the strict
  # reading of "35 KB" (PEM is ASCII, so characters are bytes).
  validation {
    condition     = length(join("\n\n", [for c in var.certificates : trimspace(c)])) <= 35000
    error_message = "custom_ca_trust_certificates must not exceed 35 KB (35000 bytes) of PEM certificate content in total, counted as AKS's certificate file (entries joined by a blank line)."
  }
}
