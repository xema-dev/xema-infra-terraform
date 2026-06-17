output "bucket" {
  description = "Spaces bucket name."
  value       = digitalocean_spaces_bucket.this.name
}

output "endpoint" {
  description = "S3-compatible Spaces endpoint URL for the bucket's region."
  value       = "https://${var.region}.digitaloceanspaces.com"
}
