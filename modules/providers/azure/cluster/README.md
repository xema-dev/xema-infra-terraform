# `providers/azure/cluster`

Azure implementation of the [`cluster` contract](../../../../docs/CONTRACTS.md#cluster).
Provisions an AKS cluster with a default (system) node pool plus any number of
additional user pools (autoscaling and taints supported), inside a virtual
network the module creates — one subnet for the nodes and one **delegated** to
PostgreSQL Flexible Server so [`managed-postgres`](../managed-postgres/README.md)
can attach privately. OIDC issuer + **workload identity** are always on.

## Usage

```hcl
module "cluster" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/cluster?ref=v0.11.0"

  name               = "acme-dev-aks"
  region             = "westeurope"
  kubernetes_version = "1.31"
  default_pool_id    = "generic"

  node_pools = {
    generic = {
      size       = "Standard_D4s_v5"
      node_count = 3
      labels     = { serve_type = "generic" }
    }
    workers = {
      size      = "Standard_D8s_v5"
      min_nodes = 1
      max_nodes = 5
      taints    = [{ key = "workload", value = "workers", effect = "NoSchedule" }]
    }
  }

  tags = { deployment = "acme-dev" }
}
```

## Notes

- **No token.** AKS hands out client-certificate credentials, so the contract's
  `token` output is always `""`; feed `client_certificate` + `client_key` to the
  `kubernetes`/`helm` providers instead (the stack does this).
- **Pool keys are AKS agent pool names** (`^[a-z][a-z0-9]{0,11}$`). The default
  pool cannot carry taints — AKS refuses it — so the module fails fast with a
  precondition rather than silently dropping them.
- The cluster runs under a **user-assigned identity** with *Network Contributor*
  on the VNet (granted before the cluster exists, which a system-assigned
  identity cannot do). Its kubelet identity is exposed as `kubelet_identity_id`
  for registry-pull grants.
- `kubernetes_version` is a prefix resolved through
  `azurerm_kubernetes_service_versions` and then `ignore_changes`d, so a new
  patch does not force a plan diff; bump the variable deliberately to upgrade.
- Networking is Azure CNI **overlay** with a standard load balancer; the three
  CIDR inputs default to non-overlapping ranges.
- The module always creates its own VNet; adopting an existing network is not
  modelled (the delegated Postgres subnet is part of the contract this module
  provides).
- The provider (`hashicorp/azurerm`) is configured by the **root/stack**, not
  here (see [CONVENTIONS.md](../../../../docs/CONVENTIONS.md)).
- Importing an existing cluster: see [import-runbook.md](../../../../docs/import-runbook.md).

| Input | Required | Description |
| --- | --- | --- |
| `name`, `region`, `kubernetes_version` | yes | cluster identity + version prefix |
| `node_pools`, `default_pool_id` | yes | pools keyed by id; which is the default |
| `resource_group_name` | no | use an existing resource group (else `"<name>-rg"` is created) |
| `vnet_id`, `node_subnet_id` | yes | the network the nodes live in — CONSUMED from `providers/azure/network`, never created here |
| `service_cidr`, `dns_service_ip`, `pod_cidr` | no | in-cluster address ranges |
| `sku_tier`, `automatic_upgrade_channel`, `authorized_ip_ranges` | no | control-plane tier, upgrades, API allow-list |
| `enable_log_analytics`, `log_analytics_retention_days`, `tags` | no | monitoring + tagging |

**Zone pinning.** Each node pool takes an optional `zones` list (each "1", "2" or
"3"); unset leaves the choice to Azure, which is the unchanged behaviour. Pin it
when the subscription marks a zone `NotAvailableForSubscription` for the pool's
VM family, which the resource SKUs API shows
(`az vm list-skus --location <region> --size <size> --zone`, read the
`restrictions`). Changing `zones` on an existing pool replaces it.

Outputs: `cluster_id`, `endpoint`, `kubeconfig_raw` (sensitive),
`cluster_ca_certificate` (sensitive), `token` (sensitive, always `""`),
`client_certificate` / `client_key` (sensitive),
`oidc_issuer_url`, `kubelet_identity_id`, `cluster_identity_principal_id`,
`resource_group_name`, `node_resource_group`, `log_analytics_workspace_id`.
