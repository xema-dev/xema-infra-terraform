output "gateway_parent_ref" {
  description = "The parentRef every HTTPRoute attaches to: the Gateway's HTTPS listener (name, namespace, section_name). Bound into the deployment's gateway.parentRef."
  value = {
    name         = local.gateway_ref.name
    namespace    = local.gateway_ref.namespace
    section_name = local.gateway_ref.https_section_name
  }

  # The release is what makes the Gateway exist (or, customer-managed, the issuer that targets it).
  depends_on = [helm_release.cluster_config]
}

output "cluster_issuer_name" {
  description = "Name of the ACME ClusterIssuer (the cert-manager.io/cluster-issuer annotation value on the Gateway)."
  value       = var.cluster_issuer_name

  depends_on = [helm_release.cluster_config]
}
