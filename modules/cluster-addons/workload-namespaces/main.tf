resource "kubernetes_namespace_v1" "this" {
  for_each = var.namespaces

  metadata {
    name   = each.value
    labels = lookup(var.labels, each.value, {})
  }

  # These namespaces are an "ensure exists" primitive — other controllers
  # (the platform, operators) freely label/annotate them. Don't fight that:
  # ignore label/annotation drift so adopting an existing namespace is a clean
  # import, never a strip of platform-managed metadata. (Labels in var.labels
  # are still applied on create.)
  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

moved {
  from = kubernetes_namespace.this
  to   = kubernetes_namespace_v1.this
}
