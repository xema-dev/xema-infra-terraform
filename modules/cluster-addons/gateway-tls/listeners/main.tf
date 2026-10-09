# Pure mapping and guards (no provider): the Gateway's HTTPS listeners, one hostname and one
# certificate each. Kept apart from the add-on so the listener rules are testable without a
# provider (or a mock) on Terraform 1.6 and OpenTofu.
locals {
  listeners = { for k, l in var.listeners : k => {
    hostname         = l.hostname
    certificate_mode = l.certificate_mode
    # managed: the module names the Secret cert-manager fills; customer_supplied: the customer's.
    secret_name = l.certificate_mode == "managed" ? "${var.gateway_name}-${k}-tls" : l.secret_name
  } }

  managed = { for k, l in local.listeners : k => l if l.certificate_mode == "managed" }

  managed_secret_names  = [for _, l in local.managed : l.secret_name]
  colliding_secrets     = sort(distinct([for k, l in local.listeners : k if l.certificate_mode == "customer_supplied" && contains(local.managed_secret_names, l.secret_name)]))
  http01_wildcards      = sort([for k, l in local.managed : k if var.tls_solver == "http01" && startswith(l.hostname, "*.")])
  outside_dns01_zones   = sort([for k, l in local.managed : k if var.tls_solver == "dns01-azure" && !anytrue([for z in var.dns01_zones : trimprefix(l.hostname, "*.") == z || endswith(trimprefix(l.hostname, "*."), ".${z}")])])
  invalid_managed_names = sort([for k, l in local.managed : k if length(l.secret_name) > 253])
}

resource "terraform_data" "guard" {
  lifecycle {
    precondition {
      condition     = length(var.listeners) > 0
      error_message = "The Gateway needs at least one HTTPS listener."
    }
    precondition {
      condition     = length(local.http01_wildcards) == 0
      error_message = "A managed wildcard hostname needs tls_solver = \"dns01-azure\": HTTP-01 cannot issue wildcard certificates. Listeners: ${join(", ", local.http01_wildcards)}."
    }
    precondition {
      condition     = var.tls_solver != "dns01-azure" || length(var.dns01_zones) > 0
      error_message = "tls_solver = \"dns01-azure\" requires the DNS zones its solver writes into."
    }
    precondition {
      condition     = length(local.outside_dns01_zones) == 0
      error_message = "Every managed hostname must sit in one of the dns01-azure zones (${join(", ", sort(var.dns01_zones))}): the solver can answer challenges only there. Add the zone, or make these listeners customer_supplied: ${join(", ", local.outside_dns01_zones)}."
    }
    precondition {
      condition     = length(local.colliding_secrets) == 0
      error_message = "A customer_supplied secret_name may not be the Secret a managed listener issues into (cert-manager would overwrite the customer's certificate). Listeners: ${join(", ", local.colliding_secrets)}."
    }
    precondition {
      condition     = length(local.invalid_managed_names) == 0
      error_message = "The managed Secret name \"<gateway_name>-<listener>-tls\" exceeds 253 characters for: ${join(", ", local.invalid_managed_names)}."
    }
  }
}

output "listeners" {
  description = "Per listener key: hostname, certificate_mode and the Secret its certificateRefs name."
  value       = local.listeners

  depends_on = [terraform_data.guard]
}

output "certificates" {
  description = "The managed listeners only, keyed by listener: the Certificate cert-manager issues (dns_names, secret_name, issuer). Customer-supplied listeners have none."
  value = { for k, l in local.managed : k => {
    name        = "${var.gateway_name}-${k}"
    dns_names   = [l.hostname]
    secret_name = l.secret_name
    issuer_name = var.cluster_issuer_name
  } }

  depends_on = [terraform_data.guard]
}
