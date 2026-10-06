# ---------------------------------------------------------------------------
# Gateway implementation
# ---------------------------------------------------------------------------

variable "gateway_implementation" {
  description = "Who provides the Gateway: \"nginx-gateway-fabric\" (this module installs the Gateway API CRDs, NGINX Gateway Fabric and the Gateway) or \"customer-managed\" (the customer's own IaC provides the CRDs and the Gateway; this module installs only cert-manager and the issuer, and requires customer_gateway)."
  type        = string
  default     = "nginx-gateway-fabric"

  validation {
    condition     = contains(["nginx-gateway-fabric", "customer-managed"], var.gateway_implementation)
    error_message = "gateway_implementation must be one of nginx-gateway-fabric, customer-managed."
  }
}

variable "customer_gateway" {
  description = <<-EOT
    The existing Gateway, for gateway_implementation = "customer-managed" (null otherwise):
      - name, namespace    : the Gateway
      - http_section_name  : its port-80 HTTP listener, where cert-manager's HTTP-01 solver route attaches
      - https_section_name : its HTTPS listener, the output gateway_parent_ref's section_name
  EOT
  type = object({
    name               = string
    namespace          = string
    http_section_name  = string
    https_section_name = string
  })
  default = null
}

# ---------------------------------------------------------------------------
# NGINX Gateway Fabric (gateway_implementation = "nginx-gateway-fabric")
# ---------------------------------------------------------------------------

variable "gateway_api_crds_namespace" {
  description = "Namespace the Helm release holding the vendored Gateway API CRDs lives in (created if absent). The CRDs themselves are cluster-scoped."
  type        = string
  default     = "gateway-api-crds"
}

variable "ngf_chart_version" {
  description = "Pinned NGINX Gateway Fabric chart version (oci://ghcr.io/nginx/charts/nginx-gateway-fabric). Its Gateway API CRD bundle version is the vendored charts/gateway-api-crds appVersion; bump them together."
  type        = string
  default     = "2.7.2"
}

variable "ngf_namespace" {
  description = "Namespace the NGINX Gateway Fabric controller is installed into (created if absent)."
  type        = string
  default     = "nginx-gateway"
}

variable "ngf_release_name" {
  description = "Helm release name of NGINX Gateway Fabric."
  type        = string
  default     = "nginx-gateway-fabric"
}

variable "ngf_values" {
  description = "Extra inline Helm values for NGINX Gateway Fabric, merged AFTER the module's own. Each entry is a YAML document string."
  type        = list(string)
  default     = []
}

variable "gateway_class_name" {
  description = "GatewayClass the NGINX Gateway Fabric release creates and the Gateway references."
  type        = string
  default     = "nginx"
}

variable "gateway_name" {
  description = "Name of the Gateway (and of its NginxProxy)."
  type        = string
  default     = "gateway"
}

variable "gateway_namespace" {
  description = "Namespace the Gateway, its NginxProxy and the ClientSettingsPolicy live in (created if absent). cert-manager issues the listener certificate here."
  type        = string
  default     = "gateway-system"
}

variable "gateway_hostname" {
  description = "Hostname of the Gateway listeners, and the name cert-manager's gateway-shim issues the listener certificate for (e.g. \"*.example.com\", which needs tls_solver = \"dns01-azure\"). Required with nginx-gateway-fabric."
  type        = string
  default     = ""
}

variable "gateway_tls_secret_name" {
  description = "Secret the HTTPS listener's certificateRefs point at and cert-manager fills."
  type        = string
  default     = "gateway-tls"
}

variable "route_namespaces" {
  description = "Namespaces whose HTTPRoutes may attach to the HTTPS listener (allowedRoutes). Required and non-empty with nginx-gateway-fabric: no namespace is trusted by default."
  type        = set(string)
  default     = []
}

variable "max_request_body_mib" {
  description = "Request-body ceiling in MiB for every route on the Gateway (NGINX Gateway Fabric ClientSettingsPolicy body.maxSize). Finite by design; a deployment's configuration tightens it."
  type        = number
  default     = 256

  validation {
    condition     = var.max_request_body_mib == floor(var.max_request_body_mib) && var.max_request_body_mib >= 1 && var.max_request_body_mib <= 9999
    error_message = "max_request_body_mib must be a whole number of MiB between 1 and 9999 (the policy's size grammar allows four digits)."
  }
}

variable "gateway_infrastructure_annotations" {
  description = "Annotations propagated to the data-plane Service — the cloud-specific knobs (e.g. an Azure DNS label, a static IP resource group, an internal LB). Passed through verbatim."
  type        = map(string)
  default     = {}
}

variable "data_plane_service_type" {
  description = "Service type of the NGINX data plane: LoadBalancer (a cloud LB), NodePort (a host-level edge such as a tunnel; set data_plane_node_ports) or ClusterIP."
  type        = string
  default     = "LoadBalancer"

  validation {
    condition     = contains(["LoadBalancer", "NodePort", "ClusterIP"], var.data_plane_service_type)
    error_message = "data_plane_service_type must be one of LoadBalancer, NodePort, ClusterIP."
  }
}

variable "data_plane_external_traffic_policy" {
  description = "externalTrafficPolicy of the data-plane Service (Local preserves the client source IP)."
  type        = string
  default     = "Local"

  validation {
    condition     = contains(["Local", "Cluster"], var.data_plane_external_traffic_policy)
    error_message = "data_plane_external_traffic_policy must be Local or Cluster."
  }
}

variable "data_plane_load_balancer_ip" {
  description = "Pin the data-plane LoadBalancer to a pre-allocated static IP. Empty lets the cloud assign one."
  type        = string
  default     = ""
}

variable "data_plane_node_ports" {
  description = "Fixed NodePorts for the data-plane Service (service type NodePort): each maps a node port to a Gateway listener port (80 or 443). Empty lets Kubernetes allocate them."
  type = list(object({
    port          = number
    listener_port = number
  }))
  default = []

  validation {
    condition     = alltrue([for p in var.data_plane_node_ports : contains([80, 443], p.listener_port)])
    error_message = "data_plane_node_ports[*].listener_port must be 80 or 443 (the Gateway's listener ports)."
  }
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
  description = "Name of the ACME ClusterIssuer (what the Gateway references in cert-manager.io/cluster-issuer). A DNS-1123 subdomain name, as Kubernetes requires of the object."
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
  description = "ACME challenge solver: \"http01\" (a cert-manager HTTPRoute on the Gateway's port-80 listener; needs public reachability of every hostname) or \"dns01-azure\" (Azure DNS via workload identity; needed for wildcard certificates)."
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
