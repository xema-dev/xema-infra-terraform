# cluster-addons/gateway-tls

Installs a Gateway API edge with the `helm` provider: the Gateway API standard CRDs (vendored, pinned), NGINX Gateway Fabric, cert-manager and an ACME `ClusterIssuer`. One `Gateway` serves many hostnames, one HTTPS listener per hostname, each with its own certificate.

## When to use it

Use it for inbound HTTPS on any cluster. A certificate is either `managed` (issued by the `ClusterIssuer`) or `customer_supplied` (a `kubernetes.io/tls` Secret the customer creates in `gateway_namespace`; nothing is issued). With `gateway_implementation = "customer-managed"` the module installs only cert-manager and the issuer.

## Usage

```hcl
module "gateway_tls" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/gateway-tls?ref=v0.13.0"

  acme_email       = "ops@example.com"
  route_namespaces = ["acme-apps"]

  listeners = {
    acme = { hostname = "*.acme.example.com", certificate_mode = "managed" }
    partner = {
      hostname         = "portal.partner.example"
      certificate_mode = "customer_supplied"
      secret_name      = "partner-portal-tls"
    }
  }

  tls_solver = "dns01-azure"
  dns01_azure = {
    subscription_id     = module.dns.subscription_id
    resource_group_name = module.dns.resource_group_name
    hosted_zone_names   = [module.dns.domain]
    client_id           = module.dns.dns01_client_id
  }
}
```

Routes attach with `module.gateway_tls.gateway_parent_refs`, one parent ref per listener. After apply, point DNS at the external address of the Service NGINX Gateway Fabric creates in `gateway_namespace`. The `helm` provider is configured by the root.

`tls_solver` is `http01` (every managed hostname must be publicly reachable; no managed wildcard) or `dns01-azure` (needed for wildcards; each managed hostname must sit in one of `dns01_azure.hosted_zone_names`). Missing companion inputs fail at plan.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `gateway_implementation` | no | Who provides the Gateway: "nginx-gateway-fabric" (this module installs the Gateway API CRDs, NGINX Gatewa... |
| `customer_gateway` | no | The existing Gateway, for gateway_implementation = "customer-managed" (null otherwise): - name, namespace :... |
| `gateway_api_crds_namespace` | no | Namespace the Helm release holding the vendored Gateway API CRDs lives in (created if absent). |
| `ngf_chart_version` | no | Pinned NGINX Gateway Fabric chart version (oci://ghcr.io/nginx/charts/nginx-gateway-fabric). |
| `ngf_chart_repository` | no | Helm repository of the NGINX Gateway Fabric chart: `oci://` or HTTPS (default `oci://ghcr.io/nginx/charts`). |
| `ngf_images` | no | Image overrides keyed `controller`, `nginx` (the data plane), each `{ repository, tag, digest }`, digest required. Rendered as `tag = "<tag>@<digest>"` (the chart has no digest key). Default `{}`. |
| `ngf_namespace` | no | Namespace the NGINX Gateway Fabric controller is installed into (created if absent). |
| `ngf_release_name` | no | Helm release name of NGINX Gateway Fabric. |
| `ngf_values` | no | Extra inline Helm values for NGINX Gateway Fabric, merged AFTER the module's own. |
| `gateway_class_name` | no | GatewayClass the NGINX Gateway Fabric release creates and the Gateway references. |
| `gateway_name` | no | Name of the Gateway (and of its NginxProxy). |
| `gateway_namespace` | no | Namespace the Gateway, its NginxProxy and the ClientSettingsPolicy live in (created if absent). |
| `listeners` | no | The Gateway's HTTPS listeners with nginx-gateway-fabric (empty with customer-managed), keyed by listener na... |
| `route_namespaces` | no | Namespaces whose HTTPRoutes may attach to every HTTPS listener (allowedRoutes). |
| `max_request_body_mib` | no | Request-body ceiling in MiB for every route on the Gateway (NGINX Gateway Fabric ClientSettingsPolicy body.... |
| `gateway_infrastructure_annotations` | no | Annotations propagated to the data-plane Service — the cloud-specific knobs (e.g, an Azure DNS label, a sta... |
| `data_plane_service_type` | no | Service type of the NGINX data plane: LoadBalancer (a cloud LB), NodePort (a host-level edge such as a tunn... |
| `data_plane_external_traffic_policy` | no | externalTrafficPolicy of the data-plane Service (Local preserves the client source IP). |
| `data_plane_load_balancer_ip` | no | Pin the data-plane LoadBalancer to a pre-allocated static IP. |
| `data_plane_node_ports` | no | Fixed NodePorts for the data-plane Service (service type NodePort): each maps a node port to a Gateway list... |
| `cert_manager_chart_version` | no | Pinned cert-manager chart version (https://charts.jetstack.io). |
| `cert_manager_chart_repository` | no | Helm repository of the cert-manager chart: HTTPS or `oci://` (default `https://charts.jetstack.io`). |
| `cert_manager_images` | no | Image overrides keyed `controller`, `webhook`, `cainjector`, `acmesolver`, `startupapicheck`, each `{ repository, tag, digest }`, digest required; rendered with the chart's own `digest` key. Default `{}`. |
| `cert_manager_namespace` | no | Namespace cert-manager is installed into (created if absent). |
| `cert_manager_service_account_name` | no | cert-manager controller service account name — the subject a dns01-azure workload identity is federated to. |
| `cert_manager_values` | no | Extra inline Helm values for cert-manager, merged AFTER the module's own. |
| `cluster_issuer_name` | no | Name of the ACME ClusterIssuer (what the Gateway references in cert-manager.io/cluster-issuer). |
| `acme_email` | no | Contact e-mail registered with the ACME account (expiry notices). |
| `acme_server` | no | ACME directory URL. |
| `tls_solver` | no | ACME challenge solver: "http01" (a cert-manager HTTPRoute on the Gateway's port-80 listener; needs public... |
| `dns01_azure` | no | Azure DNS solver settings, used only when tls_solver = "dns01-azure": - subscription_id : subscription the... |

Outputs: `gateway_parent_refs`, `cluster_issuer_name`.
