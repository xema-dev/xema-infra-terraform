# providers/azure/container-registry

An Azure Container Registry (`azurerm_container_registry`): Premium SKU, admin user off, public network access off.

## When to use it

Optional. Use it when the deployment needs its own private registry. It is reachable only through a private endpoint, which the stack composes with `providers/azure/private-endpoint`.

## Usage

```hcl
module "container_registry" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/container-registry?ref=v0.13.0"

  name   = "acmedevacr"
  region = "westeurope"

  pull_principal_ids = { kubelet = module.cluster.kubelet_identity_id }
}
```

`pull_principal_ids` grants `AcrPull` only. Grant `AcrPush` to your CI principal yourself, on the `id` output. The `azurerm` provider is configured by the root.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Registry name (5-50 lowercase letters and digits; globally unique as <name>.azurecr.io). |
| `region` | yes | Azure location (e.g, "westeurope"). |
| `pull_principal_ids` | no | Object ids of the identities granted AcrPull on the registry (e.g, the AKS kubelet identity). |
| `resource_group_name` | no | Existing resource group to create the registry in. |
| `tags` | no | Tags applied to every created resource. |

Outputs: `id`, `login_server`, `resource_group_name`, `assigned_role_names`.
