output "id" {
  description = "Resource id of the registry — the target of its private endpoint (providers/azure/private-endpoint)."
  value       = azurerm_container_registry.this.id
}

output "login_server" {
  description = "Registry login server (<name>.azurecr.io); the host image references use."
  value       = azurerm_container_registry.this.login_server
}

output "resource_group_name" {
  description = "Resource group holding the registry (created or supplied)."
  value       = local.resource_group_name
}
