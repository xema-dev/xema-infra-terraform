locals {
  # The private-link sub-resource ("group id") Azure names for each service.
  # The same closed set as providers/azure/network's private_link_services.
  subresource = {
    blob     = "blob"
    redis    = "redisCache"
    vault    = "vault"
    postgres = "postgresqlServer"
    acr      = "registry"
  }
}

# One private endpoint for ONE service, registered into that service's private
# DNS zone. Composition, not configuration: the stack calls this once per
# backing service it makes private, and the service's own module only turns
# its public endpoint off — it knows nothing about networks.
resource "azurerm_private_endpoint" "this" {
  lifecycle {
    precondition {
      condition     = !var.register_dns_record || var.private_dns_zone_id != ""
      error_message = "register_dns_record = true requires private_dns_zone_id."
    }
  }

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

  # The endpoint's A record. Registered here by default; left to the network's
  # owner when register_dns_record = false — enterprise landing zones commonly
  # register private-endpoint records in their central zones by policy, and a
  # second registration from here would contend with it. A plan-time input, not
  # inferred from the zone id: that id is often unknown until apply.
  dynamic "private_dns_zone_group" {
    for_each = var.register_dns_record ? [1] : []
    content {
      name                 = var.service
      private_dns_zone_ids = [var.private_dns_zone_id]
    }
  }
}
