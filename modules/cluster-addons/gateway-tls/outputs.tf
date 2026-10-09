output "gateway_parent_refs" {
  description = "The parentRefs HTTPRoutes attach to, one per HTTPS listener, keyed by listener name: { name, namespace, section_name }. A route for a host names the listener serving that host."
  value = { for k in local.gateway_ref.https_section_names : k => {
    name         = local.gateway_ref.name
    namespace    = local.gateway_ref.namespace
    section_name = k
  } }

  # The release is what makes the Gateway exist (or, customer-managed, the issuer that targets it).
  depends_on = [helm_release.cluster_config]
}

output "cluster_issuer_name" {
  description = "Name of the ACME ClusterIssuer (the issuerRef of every managed listener's Certificate); null when no issuer is installed (every listener customer_supplied)."
  value       = local.issuer ? var.cluster_issuer_name : null

  depends_on = [helm_release.cluster_config]
}
