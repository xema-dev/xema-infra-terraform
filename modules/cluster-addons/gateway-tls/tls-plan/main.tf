# Pure mapping and guards (no provider) for cluster-addons/gateway-tls: the Gateway's HTTPS
# listeners (one hostname and one certificate each), and whether an ACME issuer is installed at
# all. Kept apart from the add-on so every input-combination rule is testable without a provider
# (or a mock) on Terraform 1.6 and OpenTofu.
locals {
  ngf = var.gateway_implementation == "nginx-gateway-fabric"

  listeners = { for k, l in var.listeners : k => {
    hostname         = l.hostname
    certificate_mode = l.certificate_mode
    # managed: the module names the Secret cert-manager fills; customer_supplied: the customer's.
    secret_name = l.certificate_mode == "managed" ? "${var.gateway_name}-${k}-tls" : l.secret_name
  } }

  managed = { for k, l in local.listeners : k => l if l.certificate_mode == "managed" }

  # cert-manager and its ACME ClusterIssuer exist only for something to issue: a managed listener,
  # or a customer-managed Gateway, whose whole point here is the issuer. A Gateway whose listeners
  # are all customer_supplied installs neither.
  issuer = !local.ngf || length(local.managed) > 0

  managed_secret_names  = [for _, l in local.managed : l.secret_name]
  colliding_secrets     = sort(distinct([for k, l in local.listeners : k if l.certificate_mode == "customer_supplied" && contains(local.managed_secret_names, l.secret_name)]))
  http01_wildcards      = sort([for k, l in local.managed : k if var.tls_solver == "http01" && startswith(l.hostname, "*.")])
  outside_dns01_zones   = sort([for k, l in local.managed : k if var.tls_solver == "dns01-azure" && !anytrue([for z in var.dns01_zones : trimprefix(l.hostname, "*.") == z || endswith(trimprefix(l.hostname, "*."), ".${z}")])])
  invalid_managed_names = sort([for k, l in local.managed : k if length(l.secret_name) > 253])
}

resource "terraform_data" "guard" {
  lifecycle {
    precondition {
      condition     = !local.ngf || length(var.listeners) > 0
      error_message = "gateway_implementation = \"nginx-gateway-fabric\" needs at least one HTTPS listener."
    }
    precondition {
      condition     = local.ngf || length(var.listeners) == 0
      error_message = "listeners are only meaningful with gateway_implementation = \"nginx-gateway-fabric\": a customer-managed Gateway's listeners and certificates are the customer's (name them in customer_gateway.https_section_names)."
    }
    precondition {
      condition     = !local.ngf || length(var.route_namespaces) > 0
      error_message = "gateway_implementation = \"nginx-gateway-fabric\" requires a non-empty route_namespaces: no namespace may attach routes by default."
    }
    precondition {
      condition     = local.ngf || var.customer_gateway_given
      error_message = "gateway_implementation = \"customer-managed\" requires customer_gateway (the existing Gateway's name, namespace and listener names)."
    }
    precondition {
      condition     = !local.ngf || !var.customer_gateway_given
      error_message = "customer_gateway is only meaningful with gateway_implementation = \"customer-managed\"."
    }
    precondition {
      condition     = !local.issuer || (var.acme_email != null && var.tls_solver != null)
      error_message = "An ACME issuer is installed (a managed listener, or a customer-managed Gateway), so acme_email and tls_solver are required."
    }
    precondition {
      condition     = local.issuer || (var.acme_email == null && var.tls_solver == null && length(var.dns01_zones) == 0)
      error_message = "No listener is managed, so no ACME issuer is installed: acme_email, tls_solver and dns01_azure configure nothing. Remove them."
    }
    precondition {
      condition     = var.tls_solver != "dns01-azure" || length(var.dns01_zones) > 0
      error_message = "tls_solver = \"dns01-azure\" requires dns01_azure, with the DNS zones its solver writes into."
    }
    precondition {
      condition     = length(var.dns01_zones) == 0 || var.tls_solver == "dns01-azure"
      error_message = "dns01_azure is only meaningful with tls_solver = \"dns01-azure\"."
    }
    precondition {
      condition     = length(local.http01_wildcards) == 0
      error_message = "A managed wildcard hostname needs tls_solver = \"dns01-azure\": HTTP-01 cannot issue wildcard certificates. Listeners: ${join(", ", local.http01_wildcards)}."
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

output "issuer" {
  description = "Whether cert-manager and the ACME ClusterIssuer are installed: some listener is managed, or the Gateway is customer-managed."
  value       = local.issuer

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
