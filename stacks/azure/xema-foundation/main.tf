# The Azure FOUNDATION stack: what must exist BEFORE the substrate runs.
#
#   step 0  state-bucket   (modules/providers/azure/state-bucket, once)
#   step 1  THIS STACK     from anywhere — it touches only the Azure control plane
#   step 2  xema-substrate FROM THE MANAGEMENT RUNNER this stack creates, because
#                          its PostgreSQL roles and Key Vault secrets are written
#                          inside services that have no public endpoint
#
# Everything here is the deployment's own and survives a handoff untouched: the
# network, the private DNS zones and the runner. Handing over is changing the
# runner's SSH keys and allowlist and the identities granted roles — never
# moving a resource.

locals {
  dep  = var.deployment_name
  tags = merge({ "xema-deployment" = local.dep }, var.tags)
}

resource "azurerm_resource_group" "this" {
  name     = "${local.dep}-rg"
  location = var.region
  tags     = local.tags
}

module "network" {
  source = "../../../modules/providers/azure/network"

  name                = local.dep
  region              = var.region
  resource_group_name = azurerm_resource_group.this.name

  vnet_address_space             = var.vnet_address_space
  aks_subnet_prefix              = var.aks_subnet_prefix
  postgres_subnet_prefix         = var.postgres_subnet_prefix
  private_endpoint_subnet_prefix = var.private_endpoint_subnet_prefix
  management_subnet_prefix       = var.management_subnet_prefix
  private_link_services          = var.private_link_services

  tags = local.tags
}

module "management_runner" {
  source = "../../../modules/providers/azure/management-runner"
  count  = var.management_runner == null ? 0 : 1

  name                = "${local.dep}-runner"
  region              = var.region
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.network.management_subnet_id

  vm_size           = var.management_runner.vm_size
  ssh_public_keys   = var.management_runner.ssh_public_keys
  allowed_ssh_cidrs = var.management_runner.allowed_ssh_cidrs

  tags = local.tags
}
