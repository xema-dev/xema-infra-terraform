output "bucket" {
  description = "Spaces bucket name holding Terraform state."
  value       = digitalocean_spaces_bucket.this.name
}

output "endpoint" {
  description = "S3-compatible Spaces endpoint URL for the bucket's region."
  value       = "https://${var.region}.digitaloceanspaces.com"
}

output "backend_config_hint" {
  description = <<-EOT
    Ready-to-adapt `backend "s3" {}` block for pointing another root at this
    bucket. DO Spaces is S3-compatible, so the standard AWS-bypass skips are set.
    Replace <key> with the per-root state path. Provide credentials out-of-band
    (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY = DO Spaces key/secret), never in
    committed config.
  EOT
  value       = <<-EOT
    terraform {
      backend "s3" {
        endpoints                   = { s3 = "https://${var.region}.digitaloceanspaces.com" }
        bucket                      = "${digitalocean_spaces_bucket.this.name}"
        key                         = "<key>"        # e.g. "xema-substrate/terraform.tfstate"
        region                      = "us-east-1"    # ignored by Spaces; required by the S3 backend
        skip_credentials_validation = true
        skip_metadata_api_check     = true
        skip_region_validation      = true
      }
    }
  EOT
}
