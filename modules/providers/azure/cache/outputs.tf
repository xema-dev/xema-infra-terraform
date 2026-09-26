output "host" {
  description = "Cache hostname."
  value       = azurerm_redis_cache.this.hostname
}

output "port" {
  description = "TLS port (6380). The non-TLS port is disabled."
  value       = azurerm_redis_cache.this.ssl_port
}

output "primary_key" {
  description = "Primary access key. Treat as a credential."
  value       = azurerm_redis_cache.this.primary_access_key
  sensitive   = true
}

output "cache_id" {
  description = "Cache resource id (use as the import id)."
  value       = azurerm_redis_cache.this.id
}

output "resource_group_name" {
  description = "Resource group holding the cache (created or supplied)."
  value       = local.resource_group_name
}

output "id" {
  description = "Resource id of the cache — the target of its private endpoint (providers/azure/private-endpoint)."
  value       = azurerm_redis_cache.this.id
}
