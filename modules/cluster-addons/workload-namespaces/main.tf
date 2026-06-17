resource "kubernetes_namespace" "this" {
  for_each = var.namespaces

  metadata {
    name   = each.value
    labels = lookup(var.labels, each.value, {})
  }
}
