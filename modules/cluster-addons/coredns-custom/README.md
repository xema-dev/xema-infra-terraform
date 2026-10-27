# cluster-addons/coredns-custom

Makes pods resolve private DNS zones on an AKS cluster whose VNet uses custom DNS servers. CoreDNS forwards to the node's resolvers, which on such a VNet cannot answer Azure private DNS zones (for example `privatelink.vaultcore.azure.net`). The module sets the `azure-private-zones.server` key of the `coredns-custom` ConfigMap in `kube-system`, which AKS reads. The key holds one server block per zone, forwarding to Azure DNS (`168.63.129.16`). Azure DNS answers every private zone linked to the cluster's VNet.

## When to use it

Use it when the VNet uses custom DNS and pods must reach private endpoints. Each zone must be linked to the cluster's VNet. With no zones the module creates nothing.

## Usage

```hcl
module "coredns_custom" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/coredns-custom?ref=v0.18.1"

  zones = [
    "privatelink.vaultcore.azure.net",
    "privatelink.postgres.database.azure.com",
    "privatelink.blob.core.windows.net",
  ]
}
```

The `kubernetes` provider is configured by the root. AKS owns the `coredns-custom` ConfigMap (it creates it empty); this module owns only its `azure-private-zones.server` key (`kubernetes_config_map_v1_data`, forced, field manager `xema-infra-terraform`). Destroy removes only that key. Only one instance fits a cluster. After a change, restart CoreDNS: `kubectl -n kube-system rollout restart deployment coredns`.

The rendering is tested provider-free; the real proof that AKS accepts the key is the first apply.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `zones` | no | DNS zones CoreDNS forwards to the forwarder, one server block each. |
| `forwarder` | no | Resolver the zones are forwarded to. |

Each zone is a lowercase DNS name without a trailing dot, and zones must not repeat. The rules and the rendering are in the provider-free [`server-blocks`](server-blocks) submodule, tested by [`server-blocks/tests/server_blocks.tftest.hcl`](server-blocks/tests/server_blocks.tftest.hcl).

Outputs: `zones`.
