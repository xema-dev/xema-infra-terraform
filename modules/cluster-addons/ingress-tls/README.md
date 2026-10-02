# `cluster-addons/ingress-tls`

Cloud-agnostic ingress edge for a Xema cluster, installed with the `helm`
provider: **ingress-nginx** (a cloud `LoadBalancer`), **cert-manager** with one
ACME `ClusterIssuer`. The External Secrets Operator is its own add-on
(`cluster-addons/external-secrets`): secrets are needed whatever serves inbound
traffic. Every cloud-specific fact — a DNS zone, the identity allowed to edit it —
arrives as a plain input from the provider
primitives, so this module has no cloud provider dependency of its own.

## Usage

```hcl
module "ingress_tls" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/ingress-tls?ref=v0.1.0"

  acme_email = "ops@example.com"
  tls_solver = "dns01-azure"
  dns01_azure = {
    subscription_id     = module.dns.subscription_id
    resource_group_name = module.dns.resource_group_name
    hosted_zone_name    = module.dns.domain
    client_id           = module.dns.dns01_client_id
  }

  ingress_service_annotations = {
    "service.beta.kubernetes.io/azure-dns-label-name" = "acme-dev-ingress"
  }
}
```

## What it installs

| Release | Chart (pinned default) | Namespace |
| --- | --- | --- |
| `ingress-nginx` | `ingress-nginx` 4.15.1 | `ingress-nginx` |
| `cert-manager` | `cert-manager` v1.21.2 (CRDs installed and kept) | `cert-manager` |
| `ingress-tls-cluster-config` | the bundled local chart in `charts/cluster-config` | `cert-manager` |

The third release renders the `ClusterIssuer`. It is a custom resource whose CRD
does not exist until cert-manager is installed,
so they ship as a **local chart** instead of `kubernetes_manifest` — that resource
needs the CRD at *plan* time and cannot survive a first apply on a fresh cluster.
Helm validates them at install, once the CRDs and their admission webhooks are up.

## Closed sets

- `tls_solver`: `http01` (through the ingress; every hostname must be publicly
  reachable) or `dns01-azure` (Azure DNS through **workload identity**; needed
  for wildcard certificates). `dns01-azure` requires `dns01_azure` and labels the
  cert-manager pods `azure.workload.identity/use=true`; the identity comes from
  `providers/azure/dns`'s `dns01_workload_identity`.

A missing companion input fails at plan with a precondition naming it.

## Notes

- The LoadBalancer's external address is read **after** apply from the Service
  named by `ingress_service_name` in `ingress_namespace` — point the DNS
  records at it (the stack's `dns_records` input, or an Azure DNS label
  annotation).
- Chart versions are inputs with pinned defaults; bump them deliberately.
- `cluster_issuer_name` (default `letsencrypt`) is the object name a consumer's
  manifests reference (the `cert-manager.io/cluster-issuer` annotation). It is
  validated as a DNS-1123 subdomain name and echoed as an output, so a caller
  reads it back rather than restating the default.
- Extra values for each chart are lists of YAML documents merged AFTER the
  module's own, so a caller can override anything without forking.
- Providers (`helm`) are configured by the **root/stack**, not here (see
  [CONVENTIONS.md](../../../docs/CONVENTIONS.md)).

| Input | Required | Description |
| --- | --- | --- |
| `acme_email` | yes | ACME account contact |
| `tls_solver`, `dns01_azure`, `acme_server`, `cluster_issuer_name` | no | issuer shape |
| `ingress_*` | no | controller class, replicas, LB annotations / static IP, extra values |
| `*_chart_version`, `*_namespace`, `*_service_account_name`, `*_values` | no | pins, placement, overrides |

Outputs: `ingress_service_name`, `ingress_namespace`, `ingress_class_name`,
`cluster_issuer_name`.
