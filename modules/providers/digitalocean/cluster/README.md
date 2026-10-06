# `providers/digitalocean/cluster`

DigitalOcean implementation of the [`cluster` contract](../../../../docs/CONTRACTS.md#cluster).
Provisions a DOKS cluster with a default node pool plus any number of additional
node pools (autoscaling and taints supported — e.g. a tainted `workers` pool).

## Usage

```hcl
module "cluster" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/digitalocean/cluster?ref=v0.12.0"

  name               = "do-fra1-xema"
  region             = "fra1"
  kubernetes_version = "1.31."
  default_pool_id    = "generic"

  node_pools = {
    generic = {
      size       = "s-4vcpu-8gb"
      node_count = 3
      labels     = { serve_type = "generic" }
    }
    workers = {
      size      = "s-8vcpu-16gb"
      node_count = 2
      taints    = [{ key = "workload", value = "workers", effect = "NoSchedule" }]
    }
  }

  tags = { deployment = "acme-prod" }
}
```

## Notes

- `version` is `ignore_changes`d so DO publishing a new patch slug does not force a
  plan diff; bump `kubernetes_version` deliberately to upgrade.
- The provider (`digitalocean/digitalocean`) is configured by the **root/stack**,
  not here (see [CONVENTIONS.md](../../../../docs/CONVENTIONS.md)).
- Importing an existing cluster: see [import-runbook.md](../../../../docs/import-runbook.md).

| Input | Required | Description |
| --- | --- | --- |
| `name`, `region`, `kubernetes_version` | yes | cluster identity + version prefix |
| `node_pools`, `default_pool_id` | yes | pools keyed by id; which is the default |
| `vpc_id` | no | place in an existing VPC (else region default) |
| `auto_upgrade`, `surge_upgrade`, `tags` | no | lifecycle + tagging |

Outputs: `cluster_id`, `endpoint`, `kubeconfig_raw` (sensitive),
`cluster_ca_certificate` (sensitive), `token` (sensitive), `vpc_id`.
