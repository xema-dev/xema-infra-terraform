# The DigitalOcean Xema substrate stack. Each area is independently toggleable
# (see variables.tf § enable_*) so a deployment can manage ONLY its xema-specific
# resources (namespaces, RWX storage, identity realm, extension claims) and
# CONSUME cloud infra (cluster, database, DNS) owned by a separate Terraform.

# ---------------------------------------------------------------------------
# Cloud infra (optional — usually owned by a separate "cloud substrate" tf)
# ---------------------------------------------------------------------------

module "cluster" {
  source = "../../../modules/providers/digitalocean/cluster"
  count  = var.enable_cluster ? 1 : 0

  name               = var.cluster_name
  region             = var.region
  kubernetes_version = var.kubernetes_version
  node_pools         = var.node_pools
  default_pool_id    = var.default_pool_id
  vpc_id             = var.vpc_id
  auto_upgrade       = var.cluster_auto_upgrade
  surge_upgrade      = var.cluster_surge_upgrade
  tags               = var.tags
}

# When NOT creating the cluster, read the existing one by name so the
# kubernetes/helm providers can target it for the in-cluster addons.
data "digitalocean_kubernetes_cluster" "existing" {
  count = (!var.enable_cluster && local.needs_kube) ? 1 : 0
  name  = var.cluster_name
}

module "postgres" {
  source = "../../../modules/providers/digitalocean/managed-postgres"
  count  = var.enable_managed_postgres ? 1 : 0

  name           = var.postgres_name
  region         = var.region
  engine_version = var.postgres_engine_version
  size           = var.postgres_size
  node_count     = var.postgres_node_count

  # Attach to the cluster's VPC (created cluster) or an explicit VPC, when set.
  vpc_id = var.vpc_id != "" ? var.vpc_id : (var.enable_cluster ? one(module.cluster[*].vpc_id) : "")

  databases = var.postgres_databases
  roles     = var.postgres_roles
  tags      = var.tags
}

module "dns" {
  source = "../../../modules/providers/digitalocean/dns"
  count  = var.enable_dns ? 1 : 0

  domain = var.dns_domain

  # Base records MERGED with the extension-claimed records (extensions.tf).
  records = merge(var.dns_records, local.ext_dns_records)
}

# ---------------------------------------------------------------------------
# Xema-specific in-cluster + identity resources
# ---------------------------------------------------------------------------

module "rwx_storage" {
  source = "../../../modules/cluster-addons/rwx-storage"
  count  = var.enable_rwx_storage ? 1 : 0

  storage_class_name        = var.rwx_storage_class_name
  storage_class_provisioner = var.rwx_storage_provisioner
  chart_version             = var.rwx_chart_version
  is_default_class          = var.rwx_is_default_class
  manage_provisioner_chart  = var.rwx_manage_provisioner_chart
  allow_volume_expansion    = var.rwx_allow_volume_expansion
}

module "workload_namespaces" {
  source = "../../../modules/cluster-addons/workload-namespaces"
  count  = var.enable_workload_namespaces ? 1 : 0

  namespaces = var.workload_namespaces
  labels     = var.workload_namespace_labels
}

module "identity_realm" {
  source = "../../../modules/identity-realm"
  count  = var.enable_identity_realm ? 1 : 0

  realm_name       = var.realm_name
  display_name     = var.realm_display_name
  clients          = var.realm_clients
  realm_roles      = var.realm_roles
  protocol_mappers = var.realm_protocol_mappers
}
