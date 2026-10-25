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
# Network: CONSUMED, never created. providers/azure/network owns the VNet and
# its subnets, because the network must exist before the cluster does — the
# management runner inside it is where the stack's data-plane resources are
# applied from — and because one network serves the cluster, the PostgreSQL
# server and every private endpoint alike.
# ---------------------------------------------------------------------------

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
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
  # A managed identity: stated, so an assigner limited to service principals (an ABAC condition)
  # can evaluate the request, and a freshly created identity is not looked up before it replicates.
  principal_type = "ServicePrincipal"
}

# With outbound_type = "userDefinedRouting" the nodes' subnet carries a route
# table the network's owner controls (typically 0.0.0.0/0 -> their firewall).
# AKS validates at create time that its identity may use that route table; it
# neither creates nor edits the routes. The grant is a PERMISSION on a resource
# this module does not own — the route table itself is never managed here.
resource "azurerm_role_assignment" "cluster_route_table" {
  count = var.route_table_id != "" ? 1 : 0

  scope                = var.route_table_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
  # A managed identity: stated, so an assigner limited to service principals (an ABAC condition)
  # can evaluate the request, and a freshly created identity is not looked up before it replicates.
  principal_type = "ServicePrincipal"
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

module "network_policy_engine" {
  source = "../network-policy-engine"
  engine = var.network_policy_engine
}

# Private CAs the nodes trust: validated and mapped provider-free, so the rules
# are tested on both engines (node-ca-trust/tests).
module "node_ca_trust" {
  source       = "../node-ca-trust"
  certificates = var.custom_ca_trust_certificates
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

  # API server reachability. A PRIVATE cluster exposes its API only on a private
  # address inside the VNet. private_cluster_public_fqdn_enabled additionally
  # publishes that private address under a PUBLIC DNS name, so clients whose
  # resolvers cannot see Azure private DNS zones (a VNet on custom DNS) still
  # resolve it — the endpoint stays private either way.
  private_cluster_enabled             = var.private_cluster_enabled
  private_cluster_public_fqdn_enabled = var.private_cluster_enabled ? var.private_cluster_public_fqdn_enabled : null

  # Local (certificate) accounts off means every human and machine reaches the
  # API through Microsoft Entra ID, and Kubernetes authorization is Azure RBAC.
  local_account_disabled = var.entra_rbac == null ? null : var.entra_rbac.local_account_disabled

  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.entra_rbac == null ? [] : [var.entra_rbac]
    content {
      tenant_id              = azure_active_directory_role_based_access_control.value.tenant_id != "" ? azure_active_directory_role_based_access_control.value.tenant_id : null
      azure_rbac_enabled     = true
      admin_group_object_ids = azure_active_directory_role_based_access_control.value.admin_group_object_ids
    }
  }

  # Workload identity is always ON: it is what lets in-cluster operators
  # (External Secrets, cert-manager) hold Azure roles without a stored secret.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Private CAs every node trusts (e.g. a TLS-inspecting egress proxy, a private
  # registry). null when none are given, so existing clusters plan no change.
  # Changing the set rolls every node (AKS replaces them with the new trust).
  custom_ca_trust_certificates_base64 = module.node_ca_trust.custom_ca_trust_certificates_base64

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  default_node_pool {
    name                 = var.default_pool_id
    vm_size              = local.default_pool.size
    vnet_subnet_id       = var.node_subnet_id
    node_count           = local.default_pool.min_nodes == null ? local.default_pool.node_count : null
    auto_scaling_enabled = local.default_pool.min_nodes != null
    min_count            = local.default_pool.min_nodes
    max_count            = local.default_pool.max_nodes
    node_labels          = local.default_pool.labels
    zones                = local.default_pool.zones
    os_disk_size_gb      = local.default_pool.os_disk_size_gb
    os_disk_type         = local.default_pool.os_disk_type
    # AKS needs a second pool name to rotate the default pool in place when an
    # immutable attribute (vm_size, subnet) changes; without it such a change
    # forces a whole-cluster replacement.
    temporary_name_for_rotation = "${substr(var.default_pool_id, 0, 8)}tmp"
    tags                        = var.tags
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    # A NetworkPolicy engine is ALWAYS on (no "none"): without one AKS silently ignores every
    # NetworkPolicy. cilium is the Azure CNI Powered by Cilium dataplane (its own policy engine);
    # azure / calico keep the Azure dataplane (calico: Azure CNI overlay supports it).
    network_data_plane = module.network_policy_engine.network_data_plane
    network_policy     = module.network_policy_engine.network_policy
    load_balancer_sku  = "standard"
    # "loadBalancer" (default) lets AKS give the cluster its own public egress
    # address. "userDefinedRouting" creates NO egress of its own: the nodes'
    # subnet must already route 0.0.0.0/0 somewhere (a firewall/NVA) — the
    # network owner's route, consumed as is.
    outbound_type  = var.outbound_type
    service_cidr   = var.service_cidr
    dns_service_ip = var.dns_service_ip
    pod_cidr       = var.pod_cidr
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

  depends_on = [azurerm_role_assignment.cluster_network, azurerm_role_assignment.cluster_route_table]

  lifecycle {
    # The control-plane version is upgraded deliberately, not on every plan as
    # Azure publishes new patches. Manage upgrades via a tracked variable bump.
    ignore_changes = [kubernetes_version, default_node_pool[0].orchestrator_version]

    precondition {
      condition     = !(var.private_cluster_enabled && length(var.authorized_ip_ranges) > 0)
      error_message = "authorized_ip_ranges restricts a PUBLIC API endpoint; a private cluster has none. Leave authorized_ip_ranges empty when private_cluster_enabled = true."
    }

    precondition {
      condition     = var.outbound_type != "userDefinedRouting" || var.route_table_id != ""
      error_message = "outbound_type = \"userDefinedRouting\" requires route_table_id: the route table on the nodes' subnet, which the cluster identity must be allowed to use."
    }

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
  vnet_subnet_id        = var.node_subnet_id
  mode                  = "User"
  node_count            = each.value.min_nodes == null ? each.value.node_count : null
  auto_scaling_enabled  = each.value.min_nodes != null
  min_count             = each.value.min_nodes
  max_count             = each.value.max_nodes
  node_labels           = each.value.labels
  zones                 = each.value.zones
  os_disk_size_gb       = each.value.os_disk_size_gb
  os_disk_type          = each.value.os_disk_type
  node_taints           = local.taint_strings[each.key]
  tags                  = var.tags

  lifecycle {
    ignore_changes = [orchestrator_version]
  }
}
