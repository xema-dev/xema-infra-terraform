resource "digitalocean_domain" "this" {
  name = var.domain
}

resource "digitalocean_record" "this" {
  for_each = var.records

  domain = digitalocean_domain.this.name
  name   = each.value.name
  type   = each.value.type
  value  = each.value.value
  ttl    = each.value.ttl
}
