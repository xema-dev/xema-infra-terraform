resource "digitalocean_spaces_bucket" "this" {
  name   = var.name
  region = var.region
  acl    = var.acl

  versioning {
    enabled = var.versioning
  }
}

# Opt-in only: no resource (no rules) by default. Managed here, so an apply keeps them.
resource "digitalocean_spaces_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) == 0 ? 0 : 1

  bucket = digitalocean_spaces_bucket.this.id
  region = var.region

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_origins = cors_rule.value.allowed_origins
      allowed_methods = cors_rule.value.allowed_methods
      allowed_headers = cors_rule.value.allowed_headers
      expose_headers  = cors_rule.value.exposed_headers
      max_age_seconds = cors_rule.value.max_age == 0 ? null : cors_rule.value.max_age
    }
  }
}
