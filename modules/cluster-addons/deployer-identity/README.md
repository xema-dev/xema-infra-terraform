# cluster-addons/deployer-identity

Creates the namespaces a deployment owns, a least-privileged ServiceAccount its pipeline deploys as, that account's token, and the facts that identify the cluster it reaches.

## When to use it

Use it so the pipeline kubeconfig is an output of the same apply that creates the cluster, instead of a manifest applied by hand with cluster-admin. The authority is namespaced; the only cluster-scoped grant is read-only, limited to `kube-system` and the deployment's namespace, so a deploy can verify which cluster it targets.

## Usage

```hcl
module "deployer_identity" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/deployer-identity?ref=v1.0.0"

  deployment_name       = "acme-prod"
  namespace             = "acme-prod"
  additional_namespaces = ["acme-prod-infra"]

  cluster_endpoint           = module.cluster.endpoint
  cluster_ca_certificate_b64 = module.cluster.cluster_ca_certificate
}
```

Then read the kubeconfig: `terraform output -raw deployer_kubeconfig`. To rotate the token, taint the token Secret and apply.

`namespace` is declared, never derived from a directory name. `cluster_identity` emits the API server endpoint, the sha256 of the cluster CA and the UID of `kube-system`; a consumer recomputes them and refuses to write when any differs.

The `kubernetes` provider is configured by the root, not here.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `deployment_name` | yes | The deployment this identity belongs to. |
| `namespace` | yes | The namespace the deployment's workloads run in — the one its own descriptor DECLARES. |
| `additional_namespaces` | no | Every OTHER namespace the same identity deploys into — typically the deployment's infrastructure namespace. |
| `service_account_name` | no | Name of the deployer ServiceAccount, its Role and its RoleBindings. |
| `manage_namespaces` | no | Create the namespaces here. |
| `namespace_labels` | no | Extra labels for the namespaces this module creates, merged over the two it always sets (`xema.io/bootstrap... |
| `cluster_endpoint` | no | The Kubernetes API server URL, exactly as a kubeconfig names it. |
| `cluster_ca_certificate_b64` | no | The cluster CA, base64-encoded — the exact bytes a kubeconfig carries as `certificate-authority-data` (ever... |
| `context_name` | no | The context/cluster/user name written into the emitted kubeconfig. |
| `manage_cluster_identity_reader` | no | Grant the deployer `get` on exactly two namespaces cluster-wide — `kube-system` and its own — so a deploy c... |
| `extra_rules` | no | Additional namespaced policy rules appended to the deployer Role in EVERY namespace. |

Outputs: `namespaces`, `service_account_name`, `token_secret_name`, `deployer_token`, `deployer_kubeconfig`, `cluster_identity`.
