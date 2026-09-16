# Extension substrate claim wiring.
#
# See docs/extensions.md. The claim KIND set is CLOSED — v1 ships three kinds:
#   object_buckets    -> module.extension_bucket (DO Spaces)
#   managed_databases -> digitalocean_database_db/_user on the RESOLVED cluster
#                        (created module.postgres, or existing shared cluster)
#   dns_records       -> merged into module.dns (requires enable_dns)
#
# The flattening locals live in locals.tf (keyed by "<extension>/<claim>").

# One dedicated object-storage bucket per object_buckets claim.
module "extension_bucket" {
  source   = "../../../modules/providers/digitalocean/object-bucket"
  for_each = local.ext_buckets

  name       = each.value.name
  region     = var.region
  acl        = each.value.acl
  versioning = each.value.versioning
}

# One dedicated logical database per managed_databases claim, on the resolved
# managed-Postgres cluster. Additive — it never touches other databases on a
# shared cluster.
resource "digitalocean_database_db" "extension" {
  for_each = local.ext_databases

  cluster_id = local.ext_db_cluster_id
  name       = each.value.database

  lifecycle {
    precondition {
      condition     = local.ext_db_cluster_id != ""
      error_message = "Extension managed_databases were declared but no managed-Postgres cluster is resolved. Set enable_managed_postgres = true, or provide existing_database_cluster_id."
    }
  }
}

# Optional owner role per claim that declares one.
resource "digitalocean_database_user" "extension" {
  for_each = { for k, v in local.ext_databases : k => v if v.owner != null }

  cluster_id = local.ext_db_cluster_id
  name       = each.value.owner
}

# Fail fast (rather than silently drop) if an extension claims a DNS record but the
# dns module is disabled for this deployment.
resource "terraform_data" "extension_guards" {
  count = length(local.ext_dns) > 0 ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.enable_dns
      error_message = "Extension dns_records were declared but enable_dns = false. Enable the dns module or remove the records (DNS is managed elsewhere for this deployment)."
    }
  }
}
