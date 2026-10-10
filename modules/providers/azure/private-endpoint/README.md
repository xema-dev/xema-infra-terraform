# providers/azure/private-endpoint

One private endpoint for one backing service, registered in that service's private DNS zone, so the service's own hostname resolves to a private address inside the VNet.

`service` is one of `blob`, `redis`, `vault`, `postgres`, `acr`, matching `private_link_services` of `providers/azure/network`. The stack composes this module with the service module, which only turns its public endpoint off.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Name prefix of the endpoint and its service connection. |
| `region` | yes | Azure region (must be the VNet's). |
| `resource_group_name` | yes | Resource group to create the endpoint in. |
| `service` | yes | Which private-link service the endpoint reaches. |
| `target_resource_id` | yes | Resource id of the storage account, cache, key vault, PostgreSQL flexible server or container registry. |
| `subnet_id` | yes | Subnet the endpoint's NIC is placed in (providers/azure/network's private_endpoint_subnet_id). |
| `private_dns_zone_id` | no | Private DNS zone to register the endpoint's record in (providers/azure/network's private_dns_zone_ids[servi... |
| `register_dns_record` | no | Register the endpoint's A record in private_dns_zone_id (default true). |
| `tags` | no | Tags applied to every taggable resource. |

Outputs: `private_ip_address`, `id`.
