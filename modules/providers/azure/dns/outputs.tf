output "domain" {
  description = "The managed DNS zone apex."
  value       = azurerm_dns_zone.this.name
}

output "record_ids" {
  description = "Provider record ids keyed by the input records key."
  value = merge(
    { for k, r in azurerm_dns_a_record.this : k => r.id },
    { for k, r in azurerm_dns_aaaa_record.this : k => r.id },
    { for k, r in azurerm_dns_cname_record.this : k => r.id },
    { for k, r in azurerm_dns_txt_record.this : k => r.id },
  )
}

output "name_servers" {
  description = "Azure DNS name servers for the zone — delegate the apex to these at the registrar."
  value       = azurerm_dns_zone.this.name_servers
}

output "zone_id" {
  description = "DNS zone resource id."
  value       = azurerm_dns_zone.this.id
}

output "resource_group_name" {
  description = "Resource group holding the zone (created or supplied). cert-manager's azureDNS solver needs it."
  value       = local.resource_group_name
}

output "subscription_id" {
  description = "Subscription the zone lives in. cert-manager's azureDNS solver needs it."
  value       = data.azurerm_client_config.current.subscription_id
}

output "dns01_client_id" {
  description = "Client id of the DNS-01 solver identity; \"\" when dns01_workload_identity.enabled = false."
  value       = var.dns01_workload_identity.enabled ? azurerm_user_assigned_identity.dns01[0].client_id : ""
}

output "assigned_role_names" {
  description = "Azure role definition names this module assigns. Static: the names this module can assign, whatever the inputs, so a bootstrap's ABAC condition on the role-assignment writer can be derived before any state exists (see modules/assigned-roles)."
  value       = ["DNS Zone Contributor"]
}
