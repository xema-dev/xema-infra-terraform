resource "digitalocean_spaces_bucket" "this" {
  name   = var.name
  region = var.region
  # State buckets are always private — never expose Terraform state.
  acl = "private"

  # Versioning is forced on (not optional): it is the recovery mechanism for a
  # corrupted/overwritten state object.
  versioning {
    enabled = true
  }
}
