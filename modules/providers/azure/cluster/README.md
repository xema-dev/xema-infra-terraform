# providers/azure/cluster

An AKS cluster with a default node pool and any number of user pools (autoscaling and taints supported), plus the network it runs in: a node subnet and a subnet delegated to PostgreSQL Flexible Server. The OIDC issuer and workload identity are always on. Implements the [`cluster` contract](../../../../docs/CONTRACTS.md#cluster).

## When to use it

Use it to create the Kubernetes cluster of the Azure substrate.

## Usage

```hcl
module "cluster" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/cluster?ref=v0.13.0"

  name               = "acme-dev-aks"
  region             = "westeurope"
  kubernetes_version = "1.31"
  default_pool_id    = "generic"

  node_pools = {
    generic = { size = "Standard_D4s_v5", node_count = 3 }
    workers = {
      size      = "Standard_D8s_v5"
      min_nodes = 1
      max_nodes = 5
      taints    = [{ key = "workload", value = "workers", effect = "NoSchedule" }]
    }
  }
}
```

- Credentials are client certificates; the `token` output is always `""`.
- Pool keys are AKS agent pool names (`^[a-z][a-z0-9]{0,11}$`). The default pool cannot carry taints.
- `kubernetes_version` is a prefix; patch upgrades do not produce a plan diff.
- A NetworkPolicy engine is always enforced: `network_policy_engine` is `cilium` (default) or `calico`. Changing it on an existing cluster recreates it.
- Each pool takes optional `zones`, `os_disk_size_gb` and `os_disk_type` (`Managed` or `Ephemeral`). Changing them on an existing pool replaces it.
- The `azurerm` provider is configured by the root. To adopt an existing cluster, see [`import-runbook.md`](../../../../docs/import-runbook.md).

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Cluster name. |
| `region` | yes | Azure location (e.g, "westeurope"). |
| `kubernetes_version` | yes | AKS control-plane version prefix (e.g, "1.31"). |
| `node_pools` | yes | Node pools keyed by a stable pool id. |
| `default_pool_id` | yes | Which key in node_pools is the AKS default (system) pool. |
| `resource_group_name` | no | Existing resource group to create the cluster in. |
| `vnet_id` | yes | Virtual network the cluster's nodes live in (providers/azure/network's vnet_id). |
| `node_subnet_id` | yes | Subnet the node pools are placed in (providers/azure/network's aks_subnet_id). |
| `service_cidr` | no | Kubernetes Service CIDR. |
| `dns_service_ip` | no | Cluster DNS service IP (inside service_cidr). |
| `pod_cidr` | no | Pod CIDR for Azure CNI overlay. |
| `network_policy_engine` | no | The NetworkPolicy engine enforcing every Kubernetes NetworkPolicy on the cluster (Azure CNI overlay): - "ci... |
| `sku_tier` | no | AKS control-plane SKU tier: one of "Free", "Standard", "Premium". |
| `automatic_upgrade_channel` | no | AKS automatic upgrade channel: one of "patch", "rapid", "node-image", "stable", or "" (empty) to... |
| `authorized_ip_ranges` | no | CIDRs allowed to reach the Kubernetes API server. |
| `outbound_type` | no | AKS egress: "loadBalancer" (default — AKS provisions its own public egress address), "userDefinedRouting... |
| `route_table_id` | no | Id of the route table associated with node_subnet_id. |
| `private_cluster_enabled` | no | Expose the Kubernetes API only on a private address inside the VNet (no public endpoint). |
| `private_cluster_public_fqdn_enabled` | no | For a private cluster: also publish the API's PRIVATE address under a public DNS name, so clients on a VNet... |
| `entra_rbac` | no | Microsoft Entra ID authentication with Azure RBAC for Kubernetes authorization. |
| `enable_log_analytics` | no | Create a Log Analytics workspace and wire the AKS monitoring (oms_agent) add-on to it. |
| `log_analytics_retention_days` | no | Log Analytics retention in days (used only when enable_log_analytics). |
| `tags` | no | Tags applied to every created resource. |

Outputs: `cluster_id`, `endpoint`, `kubeconfig_raw`, `cluster_ca_certificate`, `token`, `client_certificate`, `client_key`, `oidc_issuer_url`, `kubelet_identity_id`, `cluster_identity_principal_id`, `resource_group_name`, `node_resource_group`, `log_analytics_workspace_id`, `assigned_role_names`.
