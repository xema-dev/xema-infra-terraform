output "cluster_id" {
  description = "DO managed-database cluster uuid (use as the import id)."
  value       = digitalocean_database_cluster.this.id
}

output "host" {
  description = "Private host (preferred) falling back to the public host."
  value       = digitalocean_database_cluster.this.private_host != "" ? digitalocean_database_cluster.this.private_host : digitalocean_database_cluster.this.host
}

output "port" {
  description = "Postgres port (5432 typical)."
  value       = digitalocean_database_cluster.this.port
}

output "uri" {
  description = "Admin connection URI (private URI preferred, public fallback)."
  value       = digitalocean_database_cluster.this.private_uri != "" ? digitalocean_database_cluster.this.private_uri : digitalocean_database_cluster.this.uri
  sensitive   = true
}

output "ca_certificate" {
  description = <<-EOT
    CA bundle for verify-full. DigitalOcean exposes no CA attribute on the managed
    database cluster resource, so this is always "". Fetch the CA out-of-band with
    `doctl databases get <cluster-id> --format ... ` / `doctl databases connection`
    (see README). Do not rely on this output for a CA value.
  EOT
  value       = ""
  sensitive   = true
}
