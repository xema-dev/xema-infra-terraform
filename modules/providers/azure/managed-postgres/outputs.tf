output "cluster_id" {
  description = "Flexible Server resource id (use as the import id)."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "host" {
  description = "Server FQDN. Resolves to a private address inside the linked VNet when network_access = \"private\"."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "port" {
  description = "Postgres port (always 5432 on Flexible Server)."
  value       = 5432
}

output "uri" {
  description = "Admin connection URI (sslmode=require)."
  value       = "postgres://${urlencode(var.administrator_login)}:${urlencode(local.administrator_password)}@${azurerm_postgresql_flexible_server.this.fqdn}:5432/postgres?sslmode=require"
  sensitive   = true
}

output "ca_certificate" {
  description = <<-EOT
    Always "" — and deliberately so. Azure Database for PostgreSQL Flexible
    Server serves a certificate chain anchored on PUBLIC root CAs (DigiCert
    Global Root G2 / Microsoft RSA Root CA 2017), which every operating-system
    trust store already carries, so `sslmode=verify-full` works against the
    system bundle and there is no per-server CA to export. Kept for the
    managed-postgres contract.
  EOT
  value       = ""
  sensitive   = true
}

output "administrator_login" {
  description = "Server administrator login (for the stack's postgresql provider)."
  value       = var.administrator_login
}

output "administrator_password" {
  description = "Server administrator password (supplied or generated)."
  value       = local.administrator_password
  sensitive   = true
}

output "role_passwords" {
  description = "Generated passwords keyed by role name. Treat as credentials."
  value       = { for r in var.roles : r => random_password.role[r].result }
  sensitive   = true
}

output "database_ids" {
  description = "Database resource ids keyed by database name."
  value       = { for k, d in azurerm_postgresql_flexible_server_database.this : k => d.id }
}

output "resource_group_name" {
  description = "Resource group holding the server (created or supplied)."
  value       = local.resource_group_name
}

output "private_dns_zone_id" {
  description = "Id of the private DNS zone; null when network_access = \"public\"."
  value       = one(azurerm_private_dns_zone.this[*].id)
}
