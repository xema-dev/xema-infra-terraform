output "private_ip_address" {
  description = "Private IP the service answers on inside the VNet."
  value       = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
}

output "id" {
  description = "Private endpoint id."
  value       = azurerm_private_endpoint.this.id
}
