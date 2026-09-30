locals {
  create_resource_group = var.resource_group_name == ""
  resource_group_name   = local.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  missing_values = [for n in var.secret_names : n if !contains(keys(var.secret_values), n)]
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  count = local.create_resource_group ? 1 : 0

  name     = "${var.name}-rg"
  location = var.region
  tags     = var.tags
}

resource "azurerm_key_vault" "this" {
  name                = var.name
  location            = var.region
  resource_group_name = local.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = var.tags

  # RBAC, never access policies: every grant is an azurerm_role_assignment a
  # reader can see, and the deployer needs no special-cased policy entry.
  rbac_authorization_enabled    = true
  purge_protection_enabled      = var.purge_protection_enabled
  soft_delete_retention_days    = var.soft_delete_retention_days
  public_network_access_enabled = var.public_network_access_enabled
}

# ---------------------------------------------------------------------------
# Seeded secrets. The deployer must be able to WRITE them; with RBAC vaults
# that is a role, and a freshly-granted role is eventually consistent.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "deployer" {
  # The grant exists so the principal running Terraform can write the SEEDED secrets; with none to
  # seed it would be a standing data-plane role with no purpose.
  count = var.grant_deployer_secrets_officer && length(var.secret_names) > 0 ? 1 : 0

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "rbac_propagation" {
  count = var.grant_deployer_secrets_officer && length(var.secret_names) > 0 ? 1 : 0

  create_duration = var.rbac_propagation_wait
  depends_on      = [azurerm_role_assignment.deployer]
}

resource "azurerm_key_vault_secret" "this" {
  for_each = var.secret_names

  name         = each.value
  key_vault_id = azurerm_key_vault.this.id
  value        = var.secret_values[each.value]
  tags         = var.tags

  depends_on = [time_sleep.rbac_propagation]

  lifecycle {
    precondition {
      condition     = length(local.missing_values) == 0
      error_message = "Every name in secret_names needs a value in secret_values. Missing: ${join(", ", local.missing_values)}."
    }
  }
}

# ---------------------------------------------------------------------------
# Reader identity for the in-cluster operator (workload identity).
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "reader" {
  count = var.workload_identity.enabled ? 1 : 0

  name                = "${var.name}-reader-identity"
  location            = var.region
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "reader" {
  count = var.workload_identity.enabled ? 1 : 0

  name                      = "${var.name}-reader"
  user_assigned_identity_id = azurerm_user_assigned_identity.reader[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.workload_identity.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.workload_identity.service_account_namespace}:${var.workload_identity.service_account_name}"
}

resource "azurerm_role_assignment" "reader" {
  count = var.workload_identity.enabled ? 1 : 0

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.reader[0].principal_id
  # A managed identity: stated, so an assigner limited to service principals (an ABAC condition)
  # can evaluate the request, and a freshly created identity is not looked up before it replicates.
  principal_type = "ServicePrincipal"
}
