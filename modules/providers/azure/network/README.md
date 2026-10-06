# `providers/azure/network`

The deployment's network: one VNet with four single-purpose subnets, and one
private DNS zone per private-link service, linked to the VNet.

| subnet | holds |
| --- | --- |
| `aks` | the cluster's nodes (`providers/azure/cluster` consumes it; it creates no network) |
| `postgres` | delegated to PostgreSQL Flexible Server (VNet injection) |
| `private-endpoints` | the private endpoints of the cache, storage account, key vault and container registry |
| `management` | the management runner (`providers/azure/management-runner`) |

The network is its own module because it must exist **before** the cluster and
the backing services: the management runner inside it is where the substrate's
data-plane resources are applied from. `stacks/azure/xema-foundation` composes it.

`private_link_services` is a closed set (`blob | redis | vault | postgres | acr`). Empty creates no
zones, which is right only when every backing service is public.

Outputs: `resource_group_name`, `vnet_id`, `aks_subnet_id`, `postgres_subnet_id`,
`private_endpoint_subnet_id`, `management_subnet_id`, `private_dns_zone_ids`
(keyed by service).
