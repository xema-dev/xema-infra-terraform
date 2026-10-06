# `providers/azure/private-endpoint`

One private endpoint for one backing service, registered into that service's
private DNS zone, so the service's own hostname resolves to a private address
inside the VNet.

`service` is a closed set (`blob | redis | vault | postgres | acr`), matching
`providers/azure/network`'s `private_link_services`. The service's own module
only turns its public endpoint off (`public_network_access_enabled = false`); the
network side is composed by the stack with this module, so no backing-service
module needs to know anything about networks.

Outputs: `id`, `private_ip_address`.
