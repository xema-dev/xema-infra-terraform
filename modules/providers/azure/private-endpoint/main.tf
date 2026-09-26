locals {
  # The private-link sub-resource ("group id") Azure names for each service.
  # The same closed set as providers/azure/network's private_link_services.
  subresource = {
    blob  = "blob"
    redis = "redisCache"
    vault = "vault"
  }
}

# One private endpoint for ONE service, registered into that service's private
# DNS zone. Composition, not configuration: the stack calls this once per
# backing service it makes private, and the service's own module only turns
# its public endpoint off — it knows nothing about networks.
resource "azurerm_private_endpoint" "this" {
  name                = "${var.name}-pe"
  location            = var.region
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.name}-psc"
    private_connection_resource_id = var.target_resource_id
    subresource_names              = [local.subresource[var.service]]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = var.service
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}
