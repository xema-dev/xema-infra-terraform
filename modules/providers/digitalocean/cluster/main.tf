locals {
  # DO tags are a flat list of strings; render "key:value" from the map.
  tag_list = [for k, v in var.tags : "${k}:${v}"]

  default_pool    = var.node_pools[var.default_pool_id]
  additional_pool = { for k, v in var.node_pools : k => v if k != var.default_pool_id }
}

resource "digitalocean_kubernetes_cluster" "this" {
  name          = var.name
  region        = var.region
  version       = data.digitalocean_kubernetes_versions.this.latest_version
  auto_upgrade  = var.auto_upgrade
  surge_upgrade = var.surge_upgrade
  vpc_uuid      = var.vpc_id != "" ? var.vpc_id : null
  tags          = local.tag_list

  node_pool {
    name       = var.default_pool_id
    size       = local.default_pool.size
    node_count = local.default_pool.min_nodes == null ? local.default_pool.node_count : null
    auto_scale = local.default_pool.min_nodes != null
    min_nodes  = local.default_pool.min_nodes
    max_nodes  = local.default_pool.max_nodes
    labels     = local.default_pool.labels

    dynamic "taint" {
      for_each = local.default_pool.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  lifecycle {
    # The control-plane version is upgraded deliberately, not on every plan as
    # DO releases new patch slugs. Manage upgrades via a tracked variable bump.
    ignore_changes = [version]
  }
}

data "digitalocean_kubernetes_versions" "this" {
  version_prefix = var.kubernetes_version
}

resource "digitalocean_kubernetes_node_pool" "additional" {
  for_each = local.additional_pool

  cluster_id = digitalocean_kubernetes_cluster.this.id
  name       = each.key
  size       = each.value.size
  node_count = each.value.min_nodes == null ? each.value.node_count : null
  auto_scale = each.value.min_nodes != null
  min_nodes  = each.value.min_nodes
  max_nodes  = each.value.max_nodes
  labels     = each.value.labels
  tags       = local.tag_list

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }
}
