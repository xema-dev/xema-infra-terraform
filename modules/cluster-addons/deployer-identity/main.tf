# The ONE identity a deployment pipeline uses to reach its cluster, and the two
# things that identity needs to exist: its namespaces and its grants.
#
# WHY THIS IS INFRASTRUCTURE RATHER THAN A MANIFEST SOMEBODY APPLIES
#
#   A pipeline's kubeconfig is not configuration — it is a CREDENTIAL, and it
#   can only be minted by an identity that already holds cluster-admin. That is
#   the same identity that creates the cluster. So the apply that creates a
#   cluster can create its deployer in the same run, and the kubeconfig becomes
#   an OUTPUT the deployment tooling consumes, exactly like a database endpoint.
#   Applied by hand instead, it is a step somebody performs once per deployment,
#   with cluster-admin on their laptop, and re-performs from a runbook whenever
#   a grant changes.
#
# WHY THE AUTHORITY IS NAMESPACED
#
#   A cluster is routinely shared. A cluster-admin kubeconfig handed to a deploy
#   pipeline can reach every workload on it, so the deployer gets Roles and
#   RoleBindings — never a ClusterRoleBinding, never cluster-scoped write. A
#   chart that renders a cluster-scoped resource fails here EXPLICITLY, which is
#   correct: that is a decision an administrator takes, not a permission to
#   pre-grant.
#
#   The single exception is read-only and named: `get` on `kube-system` and on
#   the deployment's own namespace, limited by `resourceNames`, so a deploy can
#   prove which cluster it is pointed at before writing.

locals {
  # `namespace` first and deduplicated: the ServiceAccount lives in it, and a
  # caller repeating it in additional_namespaces must not produce two Roles.
  namespaces = toset(concat([var.namespace], var.additional_namespaces))

  managed_namespaces = var.manage_namespaces ? local.namespaces : toset([])

  namespace_labels = merge({
    "xema.io/bootstrap"  = "admin-prerequisite"
    "xema.io/deployment" = var.deployment_name
  }, var.namespace_labels)

  # The least-privileged deployer contract. Every entry is what a Helm release
  # of a platform service actually renders; nothing here is speculative.
  #
  # `discovery.k8s.io/endpointslices` is load-bearing rather than tidy: a reused
  # (external) backing service is published in-cluster as a selectorless Service
  # plus an EndpointSlice, and that alias plane is the FIRST thing installed. A
  # deployer without it fails the first install step with a `forbidden` naming a
  # resource nobody granted.
  #
  # `services/proxy` with `get` alone lets a deploy read a live endpoint
  # contract off a Service before rolling its consumer — the one narrow read a
  # rollout ordering check needs.
  base_rules = [
    {
      api_groups     = [""]
      resources      = ["services", "configmaps", "secrets", "serviceaccounts", "pods", "endpoints", "persistentvolumeclaims"]
      verbs          = ["get", "list", "watch", "create", "update", "patch", "delete"]
      resource_names = null
    },
    {
      api_groups     = [""]
      resources      = ["pods/log", "pods/exec"]
      verbs          = ["get", "create"]
      resource_names = null
    },
    {
      api_groups     = [""]
      resources      = ["services/proxy"]
      verbs          = ["get"]
      resource_names = null
    },
    {
      api_groups     = ["apps"]
      resources      = ["deployments", "replicasets", "statefulsets", "daemonsets"]
      verbs          = ["get", "list", "watch", "create", "update", "patch", "delete"]
      resource_names = null
    },
    {
      api_groups     = ["autoscaling"]
      resources      = ["horizontalpodautoscalers"]
      verbs          = ["get", "list", "watch", "create", "update", "patch", "delete"]
      resource_names = null
    },
    {
      api_groups     = ["batch"]
      resources      = ["jobs", "cronjobs"]
      verbs          = ["get", "list", "watch", "create", "update", "patch", "delete"]
      resource_names = null
    },
    {
      api_groups     = ["networking.k8s.io"]
      resources      = ["ingresses", "networkpolicies"]
      verbs          = ["get", "list", "watch", "create", "update", "patch", "delete"]
      resource_names = null
    },
    {
      api_groups     = ["policy"]
      resources      = ["poddisruptionbudgets"]
      verbs          = ["get", "list", "watch", "create", "update", "patch", "delete"]
      resource_names = null
    },
    {
      api_groups     = ["rbac.authorization.k8s.io"]
      resources      = ["roles", "rolebindings"]
      verbs          = ["get", "list", "watch", "create", "update", "patch", "delete"]
      resource_names = null
    },
    {
      api_groups     = ["discovery.k8s.io"]
      resources      = ["endpointslices"]
      verbs          = ["get", "list", "watch", "create", "update", "patch", "delete"]
      resource_names = null
    },
  ]

  rules = concat(local.base_rules, [
    for rule in var.extra_rules : {
      api_groups     = rule.api_groups
      resources      = rule.resources
      verbs          = rule.verbs
      resource_names = try(rule.resource_names, null)
    }
  ])

  cluster_identity_name = "${var.deployment_name}-${var.service_account_name}-cluster-identity"

  # WHETHER a CA was supplied is not itself secret, but a comparison against a
  # sensitive value inherits its sensitivity and would then infect every
  # expression built on it — including the identity fingerprint, which is
  # public material. `nonsensitive` on the emptiness test alone keeps the
  # credential sensitive and the facts about it usable.
  ca_supplied      = nonsensitive(var.cluster_ca_certificate_b64 != "")
  emits_kubeconfig = var.cluster_endpoint != "" && local.ca_supplied

  # The sha256 of the DECODED CA — the digest a consumer recomputes from a
  # flattened kubeconfig's `certificate-authority-data`. A CA certificate is
  # public material that every kubeconfig carries in clear; the input is
  # sensitive only because every provider's cluster output is, so the digest
  # says so explicitly. Same idiom, same reason, as `providers/azure/cluster`'s
  # endpoint.
  ca_certificate_sha256 = local.ca_supplied ? nonsensitive(sha256(base64decode(var.cluster_ca_certificate_b64))) : null
}

# Cross-input guards. A `validation` block sees one variable, so the two
# requirements that span inputs fail here — before anything is created, naming
# the input.
resource "terraform_data" "input_guards" {
  lifecycle {
    precondition {
      condition     = (var.cluster_endpoint == "") == (var.cluster_ca_certificate_b64 == "")
      error_message = "cluster_endpoint and cluster_ca_certificate_b64 are supplied together or not at all: a kubeconfig needs both, and an identity fingerprint over one of them would name a cluster only half-way."
    }
    precondition {
      condition     = !contains(var.additional_namespaces, var.namespace)
      error_message = "additional_namespaces repeats `namespace`. List only the OTHER namespaces this identity deploys into."
    }
  }
}

resource "kubernetes_namespace_v1" "this" {
  for_each = local.managed_namespaces

  metadata {
    name   = each.value
    labels = local.namespace_labels
  }

  # Namespaces are an "ensure exists" primitive that other controllers freely
  # label and annotate. Ignoring that drift makes adopting an existing namespace
  # a clean import rather than a strip of platform-managed metadata. (Labels are
  # still applied on create.)
  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

resource "kubernetes_service_account_v1" "deployer" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace
  }

  depends_on = [kubernetes_namespace_v1.this]
}

# A long-lived token. Kubernetes 1.24+ stopped minting one per ServiceAccount,
# so the Secret is explicit; the token controller fills it, and
# `wait_for_service_account_token` is what makes the value available to this
# run rather than on the next apply.
resource "kubernetes_secret_v1" "deployer_token" {
  metadata {
    name      = "${var.service_account_name}-token"
    namespace = var.namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.deployer.metadata[0].name
    }
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

resource "kubernetes_role_v1" "deployer" {
  for_each = local.namespaces

  metadata {
    name      = var.service_account_name
    namespace = each.value
  }

  dynamic "rule" {
    for_each = local.rules
    content {
      api_groups     = rule.value.api_groups
      resources      = rule.value.resources
      verbs          = rule.value.verbs
      resource_names = rule.value.resource_names
    }
  }

  depends_on = [kubernetes_namespace_v1.this]
}

resource "kubernetes_role_binding_v1" "deployer" {
  for_each = local.namespaces

  metadata {
    name      = var.service_account_name
    namespace = each.value
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.deployer[each.value].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.deployer.metadata[0].name
    namespace = var.namespace
  }
}

resource "kubernetes_cluster_role_v1" "cluster_identity" {
  count = var.manage_cluster_identity_reader ? 1 : 0

  metadata {
    name = local.cluster_identity_name
  }

  rule {
    api_groups     = [""]
    resources      = ["namespaces"]
    resource_names = sort(concat(["kube-system"], [var.namespace]))
    verbs          = ["get"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "cluster_identity" {
  count = var.manage_cluster_identity_reader ? 1 : 0

  metadata {
    name = local.cluster_identity_name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.cluster_identity[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.deployer.metadata[0].name
    namespace = var.namespace
  }
}

# The cluster's own identity, read live. A UID cannot be guessed, renamed or
# aliased, which is what makes it the anchor: `kube-system` is created once, by
# the cluster itself, and its UID dies with the cluster.
data "kubernetes_namespace_v1" "kube_system" {
  metadata {
    name = "kube-system"
  }
}

# The kubernetes provider deprecated the unversioned resources in favour of their `_v1`
# equivalents (same schema). These blocks move existing state across with no destroy.
moved {
  from = kubernetes_namespace.this
  to   = kubernetes_namespace_v1.this
}

moved {
  from = kubernetes_service_account.deployer
  to   = kubernetes_service_account_v1.deployer
}

moved {
  from = kubernetes_secret.deployer_token
  to   = kubernetes_secret_v1.deployer_token
}

moved {
  from = kubernetes_role.deployer
  to   = kubernetes_role_v1.deployer
}

moved {
  from = kubernetes_role_binding.deployer
  to   = kubernetes_role_binding_v1.deployer
}

moved {
  from = kubernetes_cluster_role.cluster_identity
  to   = kubernetes_cluster_role_v1.cluster_identity
}

moved {
  from = kubernetes_cluster_role_binding.cluster_identity
  to   = kubernetes_cluster_role_binding_v1.cluster_identity
}
