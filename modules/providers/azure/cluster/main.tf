locals {
  create_resource_group = var.resource_group_name == ""
  resource_group_name   = local.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  default_pool     = var.node_pools[var.default_pool_id]
  additional_pools = { for k, v in var.node_pools : k => v if k != var.default_pool_id }

  # AKS spells a taint as "key=value:Effect".
  taint_strings = {
    for k, p in var.node_pools : k => [for t in p.taints : "${t.key}=${t.value}:${t.effect}"]
  }
}

resource "azurerm_resource_group" "this" {
  count = local.create_resource_group ? 1 : 0

  name     = "${var.name}-rg"
  location = var.region
  tags     = var.tags
}

# ---------------------------------------------------------------------------
# Network: one VNet, an AKS node subnet, and a subnet DELEGATED to PostgreSQL
# Flexible Server so the managed-postgres module can attach privately.
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = "${var.name}-vnet"
  location            = var.region
  resource_group_name = local.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "aks"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.aks_subnet_prefix]
}

resource "azurerm_subnet" "postgres" {
  name                 = "postgres"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.postgres_subnet_prefix]

  delegation {
    name = "postgresql-flexible-server"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# ---------------------------------------------------------------------------
# Cluster identity. A USER-assigned identity (not system-assigned) so the
# Network Contributor grant on the VNet can exist BEFORE the cluster is created
# — a system-assigned identity does not exist until the cluster does, and AKS
# needs the grant to place nodes in a custom subnet.
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "cluster" {
  name                = "${var.name}-identity"
  location            = var.region
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "cluster_network" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

resource "azurerm_log_analytics_workspace" "this" {
  count = var.enable_log_analytics ? 1 : 0

  name                = "${var.name}-logs"
  location            = var.region
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

data "azurerm_kubernetes_service_versions" "this" {
  location       = var.region
  version_prefix = var.kubernetes_version
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.region
  resource_group_name = local.resource_group_name
  dns_prefix          = var.name
  kubernetes_version  = data.azurerm_kubernetes_service_versions.this.latest_version
  sku_tier            = var.sku_tier
  tags                = var.tags

  automatic_upgrade_channel = var.automatic_upgrade_channel != "" ? var.automatic_upgrade_channel : null

  # Workload identity is always ON: it is what lets in-cluster operators
  # (External Secrets, cert-manager) hold Azure roles without a stored secret.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  default_node_pool {
    name                 = var.default_pool_id
    vm_size              = local.default_pool.size
    vnet_subnet_id       = azurerm_subnet.aks.id
    node_count           = local.default_pool.min_nodes == null ? local.default_pool.node_count : null
    auto_scaling_enabled = local.default_pool.min_nodes != null
    min_count            = local.default_pool.min_nodes
    max_count            = local.default_pool.max_nodes
    node_labels          = local.default_pool.labels
    # AKS needs a second pool name to rotate the default pool in place when an
    # immutable attribute (vm_size, subnet) changes; without it such a change
    # forces a whole-cluster replacement.
    temporary_name_for_rotation = "${substr(var.default_pool_id, 0, 8)}tmp"
    tags                        = var.tags
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    pod_cidr            = var.pod_cidr
  }

  # Node pools are DECLARED (var.node_pools), never auto-provisioned: "Manual"
  # is the azurerm 5.x spelling of that and the block is mandatory there.
  node_provisioning_profile {
    mode = "Manual"
  }

  dynamic "api_server_access_profile" {
    for_each = length(var.authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.authorized_ip_ranges
    }
  }

  dynamic "oms_agent" {
    for_each = var.enable_log_analytics ? [1] : []
    content {
      log_analytics_workspace_id      = azurerm_log_analytics_workspace.this[0].id
      msi_auth_for_monitoring_enabled = true
    }
  }

  depends_on = [azurerm_role_assignment.cluster_network]

  lifecycle {
    # The control-plane version is upgraded deliberately, not on every plan as
    # Azure publishes new patches. Manage upgrades via a tracked variable bump.
    ignore_changes = [kubernetes_version, default_node_pool[0].orchestrator_version]

    precondition {
      condition     = length(local.default_pool.taints) == 0
      error_message = "The default (system) node pool cannot carry taints on AKS. Declare tainted pools as additional pools and point default_pool_id at an untainted one."
    }
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "additional" {
  for_each = local.additional_pools

  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = each.value.size
  vnet_subnet_id        = azurerm_subnet.aks.id
  mode                  = "User"
  node_count            = each.value.min_nodes == null ? each.value.node_count : null
  auto_scaling_enabled  = each.value.min_nodes != null
  min_count             = each.value.min_nodes
  max_count             = each.value.max_nodes
  node_labels           = each.value.labels
  node_taints           = local.taint_strings[each.key]
  tags                  = var.tags

  lifecycle {
    ignore_changes = [orchestrator_version]
  }
}
