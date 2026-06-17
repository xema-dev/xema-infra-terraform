locals {
  # DO tags are a flat list of strings; render "key:value" from the map.
  tag_list = [for k, v in var.tags : "${k}:${v}"]
}

resource "digitalocean_database_cluster" "this" {
  name       = var.name
  engine     = "pg"
  version    = var.engine_version
  size       = var.size
  region     = var.region
  node_count = var.node_count
  # null lets DO place the cluster in the region default VPC.
  private_network_uuid = var.vpc_id != "" ? var.vpc_id : null
  tags                 = local.tag_list
}

resource "digitalocean_database_db" "this" {
  for_each = var.databases

  cluster_id = digitalocean_database_cluster.this.id
  name       = each.value
}

resource "digitalocean_database_user" "this" {
  for_each = var.roles

  cluster_id = digitalocean_database_cluster.this.id
  name       = each.value
}
