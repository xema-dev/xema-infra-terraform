# ---------------------------------------------------------------------------
# ingress-nginx
# ---------------------------------------------------------------------------

variable "ingress_nginx_chart_version" {
  description = "Pinned ingress-nginx chart version (https://kubernetes.github.io/ingress-nginx)."
  type        = string
  default     = "4.15.1"
}

variable "ingress_nginx_namespace" {
  description = "Namespace the ingress controller is installed into (created if absent)."
  type        = string
  default     = "ingress-nginx"
}

variable "ingress_nginx_release_name" {
  description = "Helm release name of the ingress controller."
  type        = string
  default     = "ingress-nginx"
}

variable "ingress_class_name" {
  description = "IngressClass name the controller registers and the http01 solver uses."
  type        = string
  default     = "nginx"
}

variable "ingress_default_class" {
  description = "Mark the IngressClass as the cluster default."
  type        = bool
  default     = true
}

variable "ingress_replica_count" {
  description = "Controller replicas."
  type        = number
  default     = 2

  validation {
    condition     = var.ingress_replica_count >= 1
    error_message = "ingress_replica_count must be >= 1."
  }
}

variable "ingress_service_annotations" {
  description = "Annotations on the controller's LoadBalancer Service — the cloud-specific knobs (e.g. an Azure DNS label, a static IP resource group, an internal LB). Passed through verbatim."
  type        = map(string)
  default     = {}
}

variable "ingress_load_balancer_ip" {
  description = "Pin the LoadBalancer to a pre-allocated static IP. Empty lets the cloud assign one."
  type        = string
  default     = ""
}

variable "ingress_nginx_values" {
  description = "Extra inline Helm values for ingress-nginx, merged AFTER the module's own. Each entry is a YAML document string."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# cert-manager + ClusterIssuer
# ---------------------------------------------------------------------------

variable "cert_manager_chart_version" {
  description = "Pinned cert-manager chart version (https://charts.jetstack.io)."
  type        = string
  default     = "v1.21.2"
}

variable "cert_manager_namespace" {
  description = "Namespace cert-manager is installed into (created if absent)."
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_service_account_name" {
  description = "cert-manager controller service account name — the subject a dns01-azure workload identity is federated to."
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_values" {
  description = "Extra inline Helm values for cert-manager, merged AFTER the module's own. Each entry is a YAML document string."
  type        = list(string)
  default     = []
}

variable "cluster_issuer_name" {
  description = "Name of the ACME ClusterIssuer (what Ingress resources reference in cert-manager.io/cluster-issuer). A DNS-1123 subdomain name, as Kubernetes requires of the object."
  type        = string
  default     = "letsencrypt"

  validation {
    condition     = length(var.cluster_issuer_name) <= 253 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", var.cluster_issuer_name))
    error_message = "cluster_issuer_name must be a DNS-1123 subdomain name: lowercase letters, digits, hyphens and dots, starting and ending alphanumeric, at most 253 chars."
  }
}

variable "acme_email" {
  description = "Contact e-mail registered with the ACME account (expiry notices). Required."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.acme_email))
    error_message = "acme_email must be an e-mail address."
  }
}

variable "acme_server" {
  description = "ACME directory URL. Default is Let's Encrypt production; use https://acme-staging-v02.api.letsencrypt.org/directory while testing."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "tls_solver" {
  description = "ACME challenge solver: \"http01\" (through the ingress controller; needs public reachability of every hostname) or \"dns01-azure\" (Azure DNS via workload identity; needed for wildcard certificates)."
  type        = string
  default     = "http01"

  validation {
    condition     = contains(["http01", "dns01-azure"], var.tls_solver)
    error_message = "tls_solver must be one of http01, dns01-azure."
  }
}

variable "dns01_azure" {
  description = <<-EOT
    Azure DNS solver settings, used only when tls_solver = "dns01-azure":
      - subscription_id     : subscription the zone lives in
      - resource_group_name : resource group of the zone
      - hosted_zone_name    : the zone apex
      - client_id           : client id of the identity holding DNS Zone Contributor,
                              federated to cert-manager's service account
                              (providers/azure/dns output dns01_client_id)
      - environment         : Azure cloud (default AzurePublicCloud)
  EOT
  type = object({
    subscription_id     = string
    resource_group_name = string
    hosted_zone_name    = string
    client_id           = string
    environment         = optional(string, "AzurePublicCloud")
  })
  default = null
}

# ---------------------------------------------------------------------------
# External Secrets Operator + ClusterSecretStore
# ---------------------------------------------------------------------------

variable "external_secrets_enabled" {
  description = "Install the External Secrets Operator and its ClusterSecretStore."
  type        = bool
  default     = true
}

variable "external_secrets_chart_version" {
  description = "Pinned external-secrets chart version (https://charts.external-secrets.io)."
  type        = string
  default     = "2.10.0"
}

variable "external_secrets_namespace" {
  description = "Namespace the operator is installed into (created if absent)."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account_name" {
  description = "Operator service account name — the subject the secret store's workload identity is federated to."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_values" {
  description = "Extra inline Helm values for external-secrets, merged AFTER the module's own. Each entry is a YAML document string."
  type        = list(string)
  default     = []
}

variable "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore ExternalSecret resources reference (secretStoreRef.name). A DNS-1123 subdomain name, as Kubernetes requires of the object."
  type        = string
  default     = "platform"

  validation {
    condition     = length(var.cluster_secret_store_name) <= 253 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", var.cluster_secret_store_name))
    error_message = "cluster_secret_store_name must be a DNS-1123 subdomain name: lowercase letters, digits, hyphens and dots, starting and ending alphanumeric, at most 253 chars."
  }
}

variable "secret_store_backend" {
  description = "Which cloud secret store the ClusterSecretStore points at. Closed set; today only \"azure-key-vault\". Requires the matching *_store input."
  type        = string
  default     = "azure-key-vault"

  validation {
    condition     = contains(["azure-key-vault"], var.secret_store_backend)
    error_message = "secret_store_backend must be one of azure-key-vault."
  }
}

variable "azure_key_vault_store" {
  description = <<-EOT
    Azure Key Vault settings for the ClusterSecretStore (secret_store_backend =
    "azure-key-vault", authType WorkloadIdentity):
      - vault_uri : https://<name>.vault.azure.net/
      - client_id : client id of the reader identity federated to the operator's
                    service account (providers/azure/secrets-backend output client_id)
      - tenant_id : Entra tenant of that identity
  EOT
  type = object({
    vault_uri = string
    client_id = string
    tenant_id = string
  })
  default = null
}
