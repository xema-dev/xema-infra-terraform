# providers/azure/network

The deployment's network: one VNet with four single-purpose subnets, and one private DNS zone per private-link service, linked to the VNet.

| Subnet | Holds |
| --- | --- |
| `aks` | the cluster's nodes (consumed by `providers/azure/cluster`) |
| `postgres` | delegated to PostgreSQL Flexible Server |
| `private-endpoints` | private endpoints of the cache, storage, key vault and registry |
| `management` | the management runner |

## When to use it

Use it first, before the cluster and backing services. `stacks/azure/xema-foundation` composes it. `private_link_services` is a subset of `blob`, `redis`, `vault`, `postgres`, `acr`; empty creates no zones.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Deployment name. |
| `region` | yes | Azure region of every resource this module creates. |
| `resource_group_name` | no | Existing resource group to create the network in. |
| `vnet_address_space` | no | Address space of the virtual network. |
| `aks_subnet_prefix` | no | AKS node subnet (inside vnet_address_space). |
| `postgres_subnet_prefix` | no | Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers (inside vnet_address_space). |
| `private_endpoint_subnet_prefix` | no | Subnet the private endpoints of the other backing services live in (inside vnet_address_space). |
| `management_subnet_prefix` | no | Subnet of the management runner (inside vnet_address_space). |
| `private_link_services` | no | Private-link services this network hosts private endpoints for; one private DNS zone is created and linked... |
| `tags` | no | Tags applied to every taggable resource. |

Outputs: `resource_group_name`, `vnet_id`, `aks_subnet_id`, `postgres_subnet_id`, `private_endpoint_subnet_id`, `management_subnet_id`, `private_dns_zone_ids`.
