resource "helm_release" "this" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = var.chart_name
  version          = var.chart_version != "" ? var.chart_version : null
  namespace        = var.namespace
  create_namespace = var.create_namespace

  values = var.chart_values

  set = [for name, value in var.chart_set : {
    name  = name
    value = value
  }]
}

resource "kubernetes_storage_class" "this" {
  metadata {
    name   = var.storage_class_name
    labels = var.storage_class_labels
    annotations = var.is_default_class ? {
      "storageclass.kubernetes.io/is-default-class" = "true"
    } : {}
  }

  storage_provisioner    = var.storage_class_provisioner
  parameters             = var.storage_class_parameters
  reclaim_policy         = var.reclaim_policy
  volume_binding_mode    = var.volume_binding_mode
  allow_volume_expansion = var.allow_volume_expansion

  # The provisioner registered by the chart must exist before the class can bind.
  depends_on = [helm_release.this]
}
