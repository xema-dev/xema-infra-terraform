resource "kubernetes_secret_v1" "this" {
  for_each = var.secrets

  metadata {
    name      = coalesce(each.value.name, each.key)
    namespace = each.value.namespace
    labels    = each.value.labels
  }

  type = each.value.type
  data = sensitive(each.value.data)
}

moved {
  from = kubernetes_secret.this
  to   = kubernetes_secret_v1.this
}
