output "domain" {
  description = "The managed DNS zone apex."
  value       = digitalocean_domain.this.name
}

output "record_ids" {
  description = "Provider record ids keyed by the input records key."
  value       = { for k, r in digitalocean_record.this : k => r.id }
}
