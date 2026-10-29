# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# network_acls is opt-in VNet service-endpoint access: absent by default; when set,
# the vault denies by default, bypasses nothing and admits only the given subnets.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "00000000-0000-0000-0000-000000000001"
    }
  }
}
mock_provider "time" {}

variables {
  name                          = "kv-test"
  region                        = "westeurope"
  resource_group_name           = "rg"
  secret_values                 = {}
  public_network_access_enabled = false
}

run "default_sets_no_acl" {
  command = plan

  assert {
    condition     = length(azurerm_key_vault.this.network_acls) == 0 && azurerm_key_vault.this.public_network_access_enabled == false
    error_message = "without network_acls the vault gets no ACL block."
  }
}

run "service_endpoint_acl" {
  command = plan

  variables {
    public_network_access_enabled = true
    network_acls = {
      virtual_network_subnet_ids = [
        "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/aks",
        "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt",
      ]
    }
  }

  assert {
    condition     = azurerm_key_vault.this.network_acls[0].default_action == "Deny" && azurerm_key_vault.this.network_acls[0].bypass == "None"
    error_message = "the ACL denies by default and bypasses nothing."
  }
  assert {
    condition     = length(azurerm_key_vault.this.network_acls[0].virtual_network_subnet_ids) == 2 && length(coalesce(azurerm_key_vault.this.network_acls[0].ip_rules, [])) == 0
    error_message = "the ACL admits exactly the given subnets and no IP."
  }
}

run "acl_needs_public_access" {
  command = plan

  variables {
    network_acls = {
      virtual_network_subnet_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/aks"]
    }
  }

  expect_failures = [azurerm_key_vault.this]
}

run "acl_needs_a_subnet" {
  command = plan

  variables {
    public_network_access_enabled = true
    network_acls                  = { virtual_network_subnet_ids = [] }
  }

  expect_failures = [var.network_acls]
}
