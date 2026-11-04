# cluster-addons/cert-manager

Installs cert-manager with the `helm` provider: the chart, its pinned version and the values every install shares. CRDs are installed with the chart and kept on uninstall. No `ClusterIssuer`, no `Gateway`: those belong to [`gateway-tls`](../gateway-tls), which calls this module when it needs an issuer.

Use it directly (through the stack's `install_cert_manager`) when a workload creates cert-manager `Issuer` and `Certificate` objects of its own and nothing else here would install cert-manager.

| Input | Required | Description |
|---|---|---|
| `chart_repository` | no | HTTPS or `oci://` Helm repository (default `https://charts.jetstack.io`). |
| `chart_version` | no | Pinned chart version (default `v1.21.2`). |
| `namespace` | no | Namespace, created if absent (default `cert-manager`). |
| `service_account_name` | no | Controller service account name (default `cert-manager`). |
| `gateway_api` | no | `enableGatewayAPI`; default `false`. When `true` the caller installs the Gateway API CRDs first. |
| `workload_identity` | no | Label the controller pod for Azure workload identity (default `false`). |
| `images_values` | no | Image-override values documents (from `gateway-tls/images-plan`). |
| `values` | no | Extra inline Helm values, merged last. |

Outputs: `namespace`, `gateway_api_enabled`. Tests: `tests-mock/cert_manager.tftest.hcl`.
