output "resource_group_name" {
  description = "Resource group the network lives in."
  value       = local.resource_group_name
}

output "vnet_id" {
  description = "Virtual network id."
  value       = azurerm_virtual_network.this.id
}

output "aks_subnet_id" {
  description = "AKS node subnet id (feed to providers/azure/cluster)."
  value       = azurerm_subnet.aks.id
}

output "postgres_subnet_id" {
  description = "Subnet delegated to PostgreSQL Flexible Server (feed to providers/azure/managed-postgres as delegated_subnet_id)."
  value       = azurerm_subnet.postgres.id
}

output "private_endpoint_subnet_id" {
  description = "Subnet for private endpoints (feed to providers/azure/private-endpoint)."
  value       = azurerm_subnet.private_endpoints.id
}

output "management_subnet_id" {
  description = "Subnet of the management runner (feed to providers/azure/management-runner)."
  value       = azurerm_subnet.management.id
}

output "private_dns_zone_ids" {
  description = "Private DNS zone id per private-link service, keyed by service (blob, redis, vault, postgres, acr). Only the services in private_link_services appear."
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}
