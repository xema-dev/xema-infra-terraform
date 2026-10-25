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

  validation {
    condition     = length(join("", [for c in var.certificates : trimspace(c)])) <= 35840
    error_message = "custom_ca_trust_certificates must not exceed 35 KB of certificate content in total (an AKS limit)."
  }
}
