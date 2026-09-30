locals {
  create_resource_group = var.resource_group_name == ""
  resource_group_name   = local.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  # Azure DNS has one resource type per record type.
  a_records     = { for k, r in var.records : k => r if r.type == "A" }
  aaaa_records  = { for k, r in var.records : k => r if r.type == "AAAA" }
  cname_records = { for k, r in var.records : k => r if r.type == "CNAME" }
  txt_records   = { for k, r in var.records : k => r if r.type == "TXT" }

  # A resource-group name may not contain dots.
  rg_stem = replace(var.domain, ".", "-")
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  count = local.create_resource_group ? 1 : 0

  name     = "${local.rg_stem}-dns-rg"
  location = var.region
  tags     = var.tags

  lifecycle {
    precondition {
      condition     = var.region != ""
      error_message = "region is required when resource_group_name is empty (a resource group needs a location; the zone itself is global)."
    }
  }
}

resource "azurerm_dns_zone" "this" {
  name                = var.domain
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_dns_a_record" "this" {
  for_each = local.a_records

  name                = each.value.name
  zone_name           = azurerm_dns_zone.this.name
  resource_group_name = local.resource_group_name
  ttl                 = each.value.ttl
  records             = [each.value.value]
  tags                = var.tags
}

resource "azurerm_dns_aaaa_record" "this" {
  for_each = local.aaaa_records

  name                = each.value.name
  zone_name           = azurerm_dns_zone.this.name
  resource_group_name = local.resource_group_name
  ttl                 = each.value.ttl
  records             = [each.value.value]
  tags                = var.tags
}

resource "azurerm_dns_cname_record" "this" {
  for_each = local.cname_records

  name                = each.value.name
  zone_name           = azurerm_dns_zone.this.name
  resource_group_name = local.resource_group_name
  ttl                 = each.value.ttl
  record              = each.value.value
  tags                = var.tags
}

resource "azurerm_dns_txt_record" "this" {
  for_each = local.txt_records

  name                = each.value.name
  zone_name           = azurerm_dns_zone.this.name
  resource_group_name = local.resource_group_name
  ttl                 = each.value.ttl
  tags                = var.tags

  record {
    value = each.value.value
  }
}

# ---------------------------------------------------------------------------
# Optional: the identity cert-manager's DNS-01 solver assumes via workload
# identity. Scoped to THIS zone only.
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "dns01" {
  count = var.dns01_workload_identity.enabled ? 1 : 0

  name                = "${local.rg_stem}-dns01-identity"
  location            = var.region
  resource_group_name = local.resource_group_name
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = var.region != ""
      error_message = "region is required when dns01_workload_identity.enabled = true (a user-assigned identity needs a location)."
    }
  }
}

resource "azurerm_federated_identity_credential" "dns01" {
  count = var.dns01_workload_identity.enabled ? 1 : 0

  name                      = "${local.rg_stem}-dns01"
  user_assigned_identity_id = azurerm_user_assigned_identity.dns01[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.dns01_workload_identity.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.dns01_workload_identity.service_account_namespace}:${var.dns01_workload_identity.service_account_name}"
}

resource "azurerm_role_assignment" "dns01" {
  count = var.dns01_workload_identity.enabled ? 1 : 0

  scope                = azurerm_dns_zone.this.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.dns01[0].principal_id
  # A managed identity: stated, so an assigner limited to service principals (an ABAC condition)
  # can evaluate the request, and a freshly created identity is not looked up before it replicates.
  principal_type = "ServicePrincipal"
}
