# `providers/azure/container-registry`

An Azure Container Registry (`azurerm_container_registry`): Premium SKU (the
tier that supports private endpoints), admin user off, public network access
off. Optional: a deployment that pulls images from a registry it already has does
not need it.

## Usage

```hcl
module "container_registry" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/container-registry?ref=v0.13.0"

  name   = "acmedevacr"
  region = "westeurope"

  # AcrPull for the AKS kubelet identity, so the cluster can pull.
  pull_principal_ids = { kubelet = module.cluster.kubelet_identity_id }
}
```

## Notes

- The registry is reachable only through a private endpoint, which the stack
  composes with `providers/azure/private-endpoint` (`service = "acr"`, zone
  `privatelink.azurecr.io` from `providers/azure/network`).
- `pull_principal_ids` grants `AcrPull` only. **The CI identity that pushes images
  is not created here**: the consumer grants `AcrPush` to its own CI principal on
  the `id` output.
- The provider (`hashicorp/azurerm`) is configured by the **root/stack**, not
  here (see [CONVENTIONS.md](../../../../docs/CONVENTIONS.md)).

Outputs: `id`, `login_server`, `resource_group_name`.
