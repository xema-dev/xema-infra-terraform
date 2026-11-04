variable "chart_repository" {
  description = "Helm repository of the cert-manager chart (chart cert-manager): an HTTPS repository or an oci:// registry path. Override to pull from a private mirror."
  type        = string
  nullable    = false
  default     = "https://charts.jetstack.io"

  validation {
    condition     = can(regex("^(https?|oci)://[^[:space:]]+$", var.chart_repository))
    error_message = "chart_repository must be an https://, http:// or oci:// URL."
  }
}

variable "chart_version" {
  description = "Pinned cert-manager chart version (https://charts.jetstack.io)."
  type        = string
  nullable    = false
  default     = "v1.21.2"
}

variable "namespace" {
  description = "Namespace cert-manager is installed into (created if absent)."
  type        = string
  nullable    = false
  default     = "cert-manager"
}

variable "service_account_name" {
  description = "cert-manager controller service account name — the subject a dns01-azure workload identity is federated to."
  type        = string
  nullable    = false
  default     = "cert-manager"
}

variable "gateway_api" {
  description = "Turn on cert-manager's Gateway API support (enableGatewayAPI: the HTTP-01 gatewayHTTPRoute solver). The controller then fails to start while the Gateway API CRDs are absent, so a caller setting it installs them first (depends_on). Off installs cert-manager for its own Issuer and Certificate objects only."
  type        = bool
  nullable    = false
  default     = false
}

variable "workload_identity" {
  description = "Label the controller pod azure.workload.identity/use=true, so the Azure workload-identity webhook injects the federated token a dns01-azure solver exchanges."
  type        = bool
  nullable    = false
  default     = false
}

variable "images_values" {
  description = "Zero or one Helm values documents (YAML) rendering the cert-manager image overrides (the images-plan module's cert_manager_values)."
  type        = list(string)
  nullable    = false
  default     = []
}

variable "values" {
  description = "Extra inline Helm values for cert-manager, merged AFTER the module's own. Each entry is a YAML document string."
  type        = list(string)
  nullable    = false
  default     = []
}
