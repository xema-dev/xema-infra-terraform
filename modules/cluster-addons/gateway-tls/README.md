# `cluster-addons/gateway-tls`

Cloud-agnostic Gateway API edge for a Xema cluster, installed with the `helm`
provider: the **Gateway API standard-channel CRDs** (vendored, pinned),
**NGINX Gateway Fabric**, **cert-manager** with Gateway API integration and one
ACME `ClusterIssuer` whose HTTP-01 solver is a Gateway `HTTPRoute`. One `Gateway`
serves any number of hosts and apex domains: one HTTPS listener per hostname, each
with its own certificate, either **managed** (issued by the `ClusterIssuer`) or
**customer_supplied** (the customer's own Secret; nothing is issued). It replaces
the retired `ingress-tls` add-on (ingress-nginx): there is no `Ingress`
anywhere. The External Secrets Operator is its own add-on
(`cluster-addons/external-secrets`). Every cloud-specific fact — a DNS zone, the
identity allowed to edit it — arrives as a plain input from the provider
primitives, so this module has no cloud provider dependency of its own.

## Usage

```hcl
module "gateway_tls" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/gateway-tls?ref=v0.13.0"

  acme_email       = "ops@example.com"
  route_namespaces = ["acme-apps"]

  # One HTTPS listener per hostname; the key is the listener (sectionName) routes attach to.
  listeners = {
    acme = { hostname = "*.acme.example.com", certificate_mode = "managed" }
    partner = {
      hostname         = "portal.partner.example"
      certificate_mode = "customer_supplied"
      secret_name      = "partner-portal-tls" # a kubernetes.io/tls Secret in gateway_namespace
    }
  }

  tls_solver = "dns01-azure"
  dns01_azure = {
    subscription_id     = module.dns.subscription_id
    resource_group_name = module.dns.resource_group_name
    hosted_zone_names   = [module.dns.domain]
    client_id           = module.dns.dns01_client_id
  }

  gateway_infrastructure_annotations = {
    "service.beta.kubernetes.io/azure-dns-label-name" = "acme-dev-gateway"
  }
}

# One parentRef per listener; a route for a host attaches to the listener serving it.
output "gateway_parent_refs" { value = module.gateway_tls.gateway_parent_refs }
```

## What it installs

| Release | Chart (pinned) | Namespace |
| --- | --- | --- |
| `gateway-api-crds` | the vendored bundle in `charts/gateway-api-crds` (Gateway API **v1.6.1** standard channel, unmodified upstream `standard-install.yaml`) | `gateway-api-crds` (CRDs are cluster-scoped) |
| `nginx-gateway-fabric` | `oci://ghcr.io/nginx/charts/nginx-gateway-fabric` **2.7.2** | `nginx-gateway` |
| `cert-manager` | `cert-manager` **v1.21.2** (CRDs installed and kept; `config.enableGatewayAPI: true`) | `cert-manager` |
| `gateway-tls-cluster-config` | the bundled local chart in `charts/cluster-config` | `gateway-system` |

The first two exist only with `gateway_implementation = "nginx-gateway-fabric"`
(the default). `cert-manager` exists only when something is issued: some listener
is `managed`, or the Gateway is `customer-managed` (whose point here is the issuer).
With every listener `customer_supplied`, nothing in the module creates a
cert-manager resource, so neither cert-manager, an ACME account, a solver nor
`acme_email` exists — and setting `acme_email`, `tls_solver` or `dns01_azure` then
fails at plan. The fourth renders, from one set of values:

- the `ClusterIssuer` (only with an issuer): HTTP-01 through `gatewayHTTPRoute.parentRefs` (the Gateway's
  port-80 listener) or `dns01-azure`;
- the `Gateway` (NGF only): one `http` listener on 80, for every host, that admits
  only same-namespace routes (`allowedRoutes: Same`) - cert-manager's solver routes
  and the module's own `<gateway_name>-http-redirect` `HTTPRoute`, which answers
  `301` to `https` (the solver's longer path match still wins for challenges) - and,
  per `listeners` entry, an HTTPS listener on 443 named by its key, with its
  `hostname`, its own `certificateRefs` Secret, and `HTTPRoute`s admitted only from
  `route_namespaces`. The Gateway carries no `cert-manager.io/cluster-issuer`
  annotation, so cert-manager's gateway-shim issues nothing on its own;
- one `Certificate` per **managed** listener (NGF only): `dnsNames = [hostname]`,
  issued by the `ClusterIssuer` into `<gateway_name>-<listener>-tls`. A
  **customer_supplied** listener gets none: its `secret_name` is a
  `kubernetes.io/tls` Secret the customer creates in `gateway_namespace` (by hand,
  External Secrets, or their own issuer) and renews;
- the `NginxProxy` (NGF only): the data-plane Service type (`LoadBalancer`,
  `NodePort` with fixed `data_plane_node_ports`, `ClusterIP`);
- the `ClientSettingsPolicy` (NGF only): the request-body ceiling on the Gateway.

These are custom resources whose CRDs do not exist until the releases above are
installed, so they ship as a **local chart** instead of `kubernetes_manifest` —
that resource needs the CRD at *plan* time and cannot survive a first apply on a
fresh cluster. Helm validates them at install, once the CRDs are up.

## Closed sets

- `gateway_implementation`: `nginx-gateway-fabric` (this module installs CRDs, NGF
  and the Gateway; requires at least one `listeners` entry and a non-empty
  `route_namespaces`) or `customer-managed` (the customer's IaC provides the Gateway
  API CRDs, the Gateway, its listeners and their certificates; this module installs
  cert-manager and the issuer only, refuses `listeners`, and requires
  `customer_gateway` naming the Gateway, its port-80 listener and its HTTPS
  listeners).
- `listeners[*].certificate_mode`: `managed` (cert-manager issues it; refuses
  `secret_name`) or `customer_supplied` (requires `secret_name`; nothing issued).
- `tls_solver`: `http01` (a solver `HTTPRoute` on the port-80 listener; every
  managed hostname must be publicly reachable; no managed wildcard) or `dns01-azure`
  (Azure DNS through **workload identity**; needed for managed wildcards; every
  managed hostname must sit in one of `dns01_azure.hosted_zone_names`, one solver
  per zone, so several apexes each issue from their own zone — an apex in no zone
  is `customer_supplied` or needs `http01`).
  `dns01-azure` requires `dns01_azure` and labels the cert-manager pods
  `azure.workload.identity/use=true`; the identity comes from `providers/azure/dns`'s
  `dns01_workload_identity`.

A missing companion input fails at plan with a precondition naming it. The listener
rules and the issuer decision fail at plan too, enforced provider-free by
`./tls-plan` (tested in `tls-plan/tests`): listener names are DNS-1123 labels other than `http`, at most 63;
hostnames are lowercase DNS names (optionally `*.`), each on one listener only; a
`customer_supplied` Secret may not be a managed listener's Secret.

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
- `cluster_issuer_name` (default `letsencrypt`) is the object name every managed
  `Certificate`'s `issuerRef` names; it is validated as a DNS-1123 subdomain name and echoed as
  an output.
- Extra values for each chart are lists of YAML documents merged AFTER the
  module's own, so a caller can override anything without forking.
- Providers (`helm`) are configured by the **root/stack**, not here (see
  [CONVENTIONS.md](../../../docs/CONVENTIONS.md)).

| Input | Required | Description |
| --- | --- | --- |
| `acme_email`, `tls_solver` | exactly with an issuer | ACME account contact and challenge solver; refused when every listener is `customer_supplied` |
| `listeners`, `route_namespaces` | with NGF | one HTTPS listener per hostname with its certificate mode, and the namespaces whose routes may attach |
| `customer_gateway` | with `customer-managed` | the existing Gateway, its port-80 listener and its HTTPS listeners |
| `dns01_azure`, `acme_server`, `cluster_issuer_name` | no | issuer shape |
| `gateway_*`, `data_plane_*`, `max_request_body_mib` | no | Gateway placement, data-plane Service, body ceiling |
| `*_chart_version`, `*_namespace`, `*_service_account_name`, `*_values` | no | pins, placement, overrides |

Outputs: `gateway_parent_refs` (keyed by HTTPS listener: `{ name, namespace, section_name }`),
`cluster_issuer_name` (`null` without an issuer).
