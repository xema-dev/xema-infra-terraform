output "network" {
  description = "The network, in exactly the shape stacks/azure/xema-substrate takes as `network`. Pass it through unchanged."
  value = {
    resource_group_name        = module.network.resource_group_name
    vnet_id                    = module.network.vnet_id
    aks_subnet_id              = module.network.aks_subnet_id
    postgres_subnet_id         = module.network.postgres_subnet_id
    private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
    private_dns_zone_ids       = module.network.private_dns_zone_ids
  }
}

output "management_runner" {
  description = "How to reach the runner (ssh <admin_username>@<public_ip_address>), and its managed identity. Add public_ip_address to the substrate's cluster_authorized_ip_ranges so the runner can reach the Kubernetes API. null when no runner."
  value = var.management_runner == null ? null : {
    public_ip_address  = one(module.management_runner[*].public_ip_address)
    private_ip_address = one(module.management_runner[*].private_ip_address)
    admin_username     = one(module.management_runner[*].admin_username)
    principal_id       = one(module.management_runner[*].principal_id)
  }
}
