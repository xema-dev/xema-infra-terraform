resource "kubernetes_secret" "this" {
  for_each = var.secrets

  metadata {
    name      = coalesce(each.value.name, each.key)
    namespace = each.value.namespace
    labels    = each.value.labels
  }

  type = each.value.type
  data = sensitive(each.value.data)
}
