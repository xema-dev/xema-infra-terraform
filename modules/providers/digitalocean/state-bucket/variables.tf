variable "name" {
  description = "Globally-unique Spaces bucket name dedicated to Terraform state."
  type        = string
}

variable "region" {
  description = <<-EOT
    DO Spaces region slug. Generic — not validated against a fixed list so new DO
    regions work without a module change. Supported at time of writing:
    nyc3, ams3, sgp1, sfo2, sfo3, fra1, syd1, blr1.
  EOT
  type        = string
}
