variable "deployment_name" {
  description = <<-EOT
    The deployment this identity belongs to. It NAMES the cluster-scoped objects
    (which must be unique per deployment on a shared cluster) and labels the
    namespaces. It is NOT the namespace and NOT a directory name: a deployment
    may be called `xema-prod` while its namespace is `xema-prod` on one cluster
    and something else on another, and the directory that happens to hold its
    files is not a fact about the cluster at all.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.deployment_name))
    error_message = "deployment_name must be a DNS-1123 label (1-63 lowercase alphanumerics or hyphens, starting and ending alphanumeric)."
  }
}

variable "namespace" {
  description = <<-EOT
    The namespace the deployment's workloads run in — the one its own
    descriptor DECLARES. REQUIRED, no default, and deliberately not derivable:
    a namespace inferred from a directory name is the defect this input exists
    to refuse (measured: a resolver required a namespace `owl-xema-prod` for a
    deployment that declares `xema-prod`).

    The ServiceAccount and its token Secret live here.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a DNS-1123 label (1-63 lowercase alphanumerics or hyphens, starting and ending alphanumeric)."
  }
}

variable "additional_namespaces" {
  description = <<-EOT
    Every OTHER namespace the same identity deploys into — typically the
    deployment's infrastructure namespace. Each gets the same Role, bound to
    the one ServiceAccount. Empty means the deployment owns a single namespace;
    nothing is derived from `namespace` (no implicit `-infra` suffix).
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ns in var.additional_namespaces : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", ns))])
    error_message = "Each additional namespace must be a DNS-1123 label."
  }
}

variable "service_account_name" {
  description = "Name of the deployer ServiceAccount, its Role and its RoleBindings. The token Secret is `<name>-token`."
  type        = string
  default     = "github-deployer"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]{0,61}[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a DNS-1123 subdomain segment."
  }
}

variable "manage_namespaces" {
  description = <<-EOT
    Create the namespaces here. Set false when they already exist and are owned
    by something else (the customer's platform team, another root, or this
    repository's `cluster-addons/workload-namespaces`): the Roles and bindings
    are still created inside them. Adopting existing namespaces INTO this module
    is an import, not a flag — see the README.
  EOT
  type        = bool
  default     = true
}

variable "namespace_labels" {
  description = "Extra labels for the namespaces this module creates, merged over the two it always sets (`xema.io/bootstrap`, `xema.io/deployment`). Ignored when manage_namespaces = false."
  type        = map(string)
  default     = {}
}

variable "cluster_endpoint" {
  description = <<-EOT
    The Kubernetes API server URL, exactly as a kubeconfig names it. Supplied by
    the caller (the stack passes the created or consumed cluster's endpoint)
    rather than read here, because a module that guessed it would be asserting a
    fact about a cluster it did not create.

    Empty with `cluster_ca_certificate_b64` empty means: emit no kubeconfig and
    no server/CA identity. Emptying exactly one of the two is refused.
  EOT
  type        = string
  default     = ""
}

variable "cluster_ca_certificate_b64" {
  description = <<-EOT
    The cluster CA, base64-encoded — the exact bytes a kubeconfig carries as
    `certificate-authority-data` (every provider's cluster module outputs it in
    this form). The identity fingerprint is the sha256 of the DECODED bytes,
    which is what a consumer recomputes from a flattened kubeconfig.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "context_name" {
  description = <<-EOT
    The context/cluster/user name written into the emitted kubeconfig. A context
    name is an ALIAS chosen by whoever wrote the file — it identifies no cluster
    — so nothing here derives authority from it. It is an input only because a
    consumer that still compares an alias needs the alias to match; the durable
    identity is the `cluster_identity` output.
  EOT
  type        = string
  default     = "default"
}

variable "manage_cluster_identity_reader" {
  description = <<-EOT
    Grant the deployer `get` on exactly two namespaces cluster-wide —
    `kube-system` and its own — so a deploy can PROVE which cluster it is
    pointed at before it writes anything. This is the one cluster-scoped grant
    the identity holds, it is read-only, and it is limited by `resourceNames`;
    without it the proof step fails `forbidden` and the deploy is refused.
  EOT
  type        = bool
  default     = true
}

variable "extra_rules" {
  description = <<-EOT
    Additional namespaced policy rules appended to the deployer Role in EVERY
    namespace. For a chart that renders a resource kind the base contract does
    not cover. Cluster-scoped authority is deliberately not expressible here.
  EOT
  type = list(object({
    api_groups     = list(string)
    resources      = list(string)
    verbs          = list(string)
    resource_names = optional(list(string))
  }))
  default = []
}
