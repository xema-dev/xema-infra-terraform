module "cluster_admin" {
  source = "../../modules/cluster-addons/cluster-admin-bootstrap"

  chart_path     = "${path.root}/../../bootstrap/cluster-admin"
  apply_via      = "run-command"
  aks_cluster_id = var.aks_cluster_id
}

output "chart_version" {
  value = module.cluster_admin.chart_version
}
