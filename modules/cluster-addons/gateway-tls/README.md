# `cluster-addons/gateway-tls`

Cloud-agnostic Gateway API edge for a Xema cluster, installed with the `helm`
provider: the **Gateway API standard-channel CRDs** (vendored, pinned),
**NGINX Gateway Fabric**, **cert-manager** with Gateway API integration and one
ACME `ClusterIssuer` whose HTTP-01 solver is a Gateway `HTTPRoute`. It replaces
the retired `ingress-tls` add-on (ingress-nginx): there is no `Ingress`
anywhere. The External Secrets Operator is its own add-on
(`cluster-addons/external-secrets`). Every cloud-specific fact — a DNS zone, the
identity allowed to edit it — arrives as a plain input from the provider
primitives, so this module has no cloud provider dependency of its own.

## Usage

```hcl
module "gateway_tls" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/gateway-tls?ref=v0.11.0"

  acme_email       = "ops@example.com"
  gateway_hostname = "*.acme.example.com"
  route_namespaces = ["acme-apps"]

  tls_solver = "dns01-azure"
  dns01_azure = {
    subscription_id     = module.dns.subscription_id
    resource_group_name = module.dns.resource_group_name
    hosted_zone_name    = module.dns.domain
    client_id           = module.dns.dns01_client_id
  }

  gateway_infrastructure_annotations = {
    "service.beta.kubernetes.io/azure-dns-label-name" = "acme-dev-gateway"
  }
}

# Every HTTPRoute attaches here; bound into the deployment's gateway.parentRef.
output "gateway_parent_ref" { value = module.gateway_tls.gateway_parent_ref }
```

## What it installs

| Release | Chart (pinned) | Namespace |
| --- | --- | --- |
| `gateway-api-crds` | the vendored bundle in `charts/gateway-api-crds` (Gateway API **v1.6.1** standard channel, unmodified upstream `standard-install.yaml`) | `gateway-api-crds` (CRDs are cluster-scoped) |
| `nginx-gateway-fabric` | `oci://ghcr.io/nginx/charts/nginx-gateway-fabric` **2.7.2** | `nginx-gateway` |
| `cert-manager` | `cert-manager` **v1.21.2** (CRDs installed and kept; `config.enableGatewayAPI: true`) | `cert-manager` |
| `gateway-tls-cluster-config` | the bundled local chart in `charts/cluster-config` | `gateway-system` |

The first two exist only with `gateway_implementation = "nginx-gateway-fabric"`
(the default). The fourth renders, from one set of values:

- the `ClusterIssuer`: HTTP-01 through `gatewayHTTPRoute.parentRefs` (the Gateway's
  port-80 listener) or `dns01-azure`;
- the `Gateway` (NGF only): an `http` listener on 80 that admits only same-namespace
  routes (`allowedRoutes: Same`) - cert-manager's solver route and the module's own
  `<gateway_name>-http-redirect` `HTTPRoute`, which answers `301` to `https` for every
  host the listener serves (the solver's longer path match still wins for challenges) - and an `https` listener on 443 that admits
  `HTTPRoute`s only from `route_namespaces`. The Gateway carries
  `cert-manager.io/cluster-issuer`, so cert-manager's gateway-shim issues the
  listener certificate into `gateway_tls_secret_name`;
- the `NginxProxy` (NGF only): the data-plane Service type (`LoadBalancer`,
  `NodePort` with fixed `data_plane_node_ports`, `ClusterIP`);
- the `ClientSettingsPolicy` (NGF only): the request-body ceiling on the Gateway.

These are custom resources whose CRDs do not exist until the releases above are
installed, so they ship as a **local chart** instead of `kubernetes_manifest` —
that resource needs the CRD at *plan* time and cannot survive a first apply on a
fresh cluster. Helm validates them at install, once the CRDs are up.

## Closed sets

- `gateway_implementation`: `nginx-gateway-fabric` (this module installs CRDs, NGF
  and the Gateway; requires `gateway_hostname` and a non-empty `route_namespaces`)
  or `customer-managed` (the customer's IaC provides the Gateway API CRDs and the
  Gateway; this module installs cert-manager and the issuer only, and requires
  `customer_gateway` naming the Gateway and its two listeners).
- `tls_solver`: `http01` (a solver `HTTPRoute` on the port-80 listener; every
  hostname must be publicly reachable; no wildcard hostname) or `dns01-azure`
  (Azure DNS through **workload identity**; needed for wildcard certificates).
  `dns01-azure` requires `dns01_azure` and labels the cert-manager pods
  `azure.workload.identity/use=true`; the identity comes from `providers/azure/dns`'s
  `dns01_workload_identity`.

A missing companion input fails at plan with a precondition naming it.

## Request body

`max_request_body_mib` (default **256**) is the `ClientSettingsPolicy`
`body.maxSize` for every route on the Gateway. It is finite by design (never `0`);
a deployment's configuration tightens it.

## Notes

- The data plane's external address is read **after** apply from the Service NGF
  creates for the Gateway in `gateway_namespace` — point the DNS records at it.
- Chart versions are inputs with pinned defaults; bump them deliberately. The
  Gateway API CRD bundle is vendored (`charts/gateway-api-crds`, `appVersion` is the
  upstream release): bump it together with `ngf_chart_version` to the version NGF's
  `config/crd/gateway-api/standard` kustomization pins.
- `cluster_issuer_name` (default `letsencrypt`) is the object name the Gateway's
  annotation references; it is validated as a DNS-1123 subdomain name and echoed as
  an output.
- Extra values for each chart are lists of YAML documents merged AFTER the
  module's own, so a caller can override anything without forking.
- Providers (`helm`) are configured by the **root/stack**, not here (see
  [CONVENTIONS.md](../../../docs/CONVENTIONS.md)).

| Input | Required | Description |
| --- | --- | --- |
| `acme_email` | yes | ACME account contact |
| `gateway_hostname`, `route_namespaces` | with NGF | listener hostname and the namespaces whose routes may attach |
| `customer_gateway` | with `customer-managed` | the existing Gateway and its listeners |
| `tls_solver`, `dns01_azure`, `acme_server`, `cluster_issuer_name` | no | issuer shape |
| `gateway_*`, `data_plane_*`, `max_request_body_mib` | no | Gateway placement, data-plane Service, body ceiling |
| `*_chart_version`, `*_namespace`, `*_service_account_name`, `*_values` | no | pins, placement, overrides |

Outputs: `gateway_parent_ref` (`{ name, namespace, section_name }`),
`cluster_issuer_name`.
