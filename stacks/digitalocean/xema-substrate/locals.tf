locals {
  # Any in-cluster resource (RWX storage, namespaces) needs a kubernetes/helm
  # connection. When the cluster is consumed (not created) we read it by name.
  needs_kube = var.enable_rwx_storage || var.enable_workload_namespaces

  # Kubernetes connection: from the created cluster, else the existing one read
  # via the data source. Null when no in-cluster resource is managed (the
  # kubernetes/helm providers then stay unconfigured but unused).
  kube_host = var.enable_cluster ? one(module.cluster[*].endpoint) : one(data.digitalocean_kubernetes_cluster.existing[*].endpoint)
  kube_token = (var.enable_cluster
    ? one(module.cluster[*].token)
  : try(one(data.digitalocean_kubernetes_cluster.existing[*].kube_config[0].token), null))
  kube_ca_b64 = (var.enable_cluster
    ? one(module.cluster[*].cluster_ca_certificate)
  : try(one(data.digitalocean_kubernetes_cluster.existing[*].kube_config[0].cluster_ca_certificate), null))

  # The managed-Postgres cluster id that hosts extension-claimed dedicated
  # databases: the created cluster, else the existing shared cluster id the
  # operator supplies.
  ext_db_cluster_id = var.enable_managed_postgres ? one(module.postgres[*].cluster_id) : var.existing_database_cluster_id

  # Extension claim flattening, keyed by "<biome>/<claim>" so adding/removing a
  # biome only adds/removes its own resources.
  ext_buckets = merge([
    for bid, e in var.extensions :
    { for k, v in e.object_buckets : "${bid}/${k}" => v }
  ]...)

  ext_databases = merge([
    for bid, e in var.extensions :
    { for k, v in e.managed_databases : "${bid}/${k}" => v }
  ]...)

  ext_dns = merge([
    for bid, e in var.extensions :
    { for k, v in e.dns_records : "${bid}/${k}" => v }
  ]...)

  # Reshaped extension DNS records, merged into the dns module's input.
  ext_dns_records = {
    for k, v in local.ext_dns : k => {
      name  = v.name
      type  = v.type
      value = v.value
      ttl   = v.ttl
    }
  }
}
