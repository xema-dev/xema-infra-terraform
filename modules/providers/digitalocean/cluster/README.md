# providers/digitalocean/cluster

A DigitalOcean Kubernetes (DOKS) cluster with a default node pool and any number of extra pools (autoscaling and taints supported). Implements the [`cluster` contract](../../../../docs/CONTRACTS.md#cluster).

## Usage

```hcl
module "cluster" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/digitalocean/cluster?ref=v0.13.0"

  name               = "do-fra1-xema"
  region             = "fra1"
  kubernetes_version = "1.31."
  default_pool_id    = "generic"

  node_pools = {
    generic = { size = "s-4vcpu-8gb", node_count = 3 }
    workers = {
      size       = "s-8vcpu-16gb"
      node_count = 2
      taints     = [{ key = "workload", value = "workers", effect = "NoSchedule" }]
    }
  }
}
```

`version` is ignored after create, so a new patch slug does not produce a plan diff; change `kubernetes_version` to upgrade. The `digitalocean` provider is configured by the root. To adopt an existing cluster, see [`import-runbook.md`](../../../../docs/import-runbook.md).

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Cluster name. |
| `region` | yes | DigitalOcean region slug (e.g, "fra1"). |
| `kubernetes_version` | yes | DOKS control-plane version slug prefix (e.g, "1.31."). |
| `node_pools` | yes | Node pools keyed by a stable pool id (e.g, "generic", "workers"). |
| `default_pool_id` | yes | Which key in node_pools is the DOKS default pool. |
| `vpc_id` | no | Existing VPC uuid to place the cluster in. |
| `auto_upgrade` | no | Enable DOKS patch auto-upgrade. |
| `surge_upgrade` | no | Enable DOKS surge upgrades. |
| `tags` | no | Tags applied to the cluster. |

Outputs: `cluster_id`, `endpoint`, `kubeconfig_raw`, `cluster_ca_certificate`, `token`, `vpc_id`.
