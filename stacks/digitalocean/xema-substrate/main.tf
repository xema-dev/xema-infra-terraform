# The DigitalOcean substrate stack. Each area is independently toggleable (see
# variables.tf § enable_*) so a deployment can manage ONLY its in-cluster and
# identity resources (namespaces, RWX storage, identity realm, extension claims)
# and CONSUME cloud infra (cluster, database, DNS) owned by a separate Terraform.
# Nothing here names a service or an application — the database and namespace
# rosters are inputs the consumer supplies.

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

  databases = var.platform_databases
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
# In-cluster + identity resources
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

# Cross-input guard. A `validation` block sees one variable, so a requirement
# that spans two fails here, naming the input, before anything is created.
resource "terraform_data" "input_guards" {
  lifecycle {
    precondition {
      condition     = !var.enable_deployer_identity || var.deployer_deployment_name != ""
      error_message = "enable_deployer_identity = true requires deployer_deployment_name: it names the cluster-scoped objects, which must be unique per deployment on a shared cluster."
    }
    precondition {
      condition     = !var.enable_deployer_identity || var.deployer_namespace != ""
      error_message = "enable_deployer_identity = true requires deployer_namespace: the namespace a deployment declares is a fact about the deployment, and the substrate refuses to invent one from deployment_name or from a directory."
    }
  }
}

module "deployer_identity" {
  source = "../../../modules/cluster-addons/deployer-identity"
  count  = var.enable_deployer_identity ? 1 : 0

  deployment_name       = var.deployer_deployment_name
  namespace             = var.deployer_namespace
  additional_namespaces = var.deployer_additional_namespaces
  service_account_name  = var.deployer_service_account_name
  manage_namespaces     = var.deployer_manage_namespaces
  context_name          = var.deployer_context_name

  cluster_endpoint           = local.kube_host != null ? local.kube_host : ""
  cluster_ca_certificate_b64 = local.kube_ca_b64 != null ? local.kube_ca_b64 : ""
}

module "identity_realm" {
  source = "../../../modules/identity-realm"
  count  = var.enable_identity_realm ? 1 : 0

  realm_name            = var.realm_name
  display_name          = var.realm_display_name
  access_token_lifespan = var.realm_access_token_lifespan
  clients               = var.realm_clients
  realm_roles           = var.realm_roles
  protocol_mappers      = var.realm_protocol_mappers
}
