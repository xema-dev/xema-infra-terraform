# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# network_rules is opt-in VNet service-endpoint access: absent by default; when set,
# the account denies by default, bypasses nothing and admits only the given subnets.

mock_provider "azurerm" {}

variables {
  name                          = "satest"
  region                        = "westeurope"
  resource_group_name           = "rg"
  public_network_access_enabled = false
}

run "default_sets_no_rules" {
  command = plan

  assert {
    condition     = length(azurerm_storage_account.this.network_rules) == 0 && azurerm_storage_account.this.public_network_access_enabled == false
    error_message = "without network_rules the account gets no rules block."
  }
}

run "service_endpoint_rules" {
  command = plan

  variables {
    public_network_access_enabled = true
    network_rules = {
      virtual_network_subnet_ids = [
        "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/aks",
        "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt",
      ]
    }
  }

  assert {
    condition     = azurerm_storage_account.this.network_rules[0].default_action == "Deny" && toset(azurerm_storage_account.this.network_rules[0].bypass) == toset(["None"])
    error_message = "the rules deny by default and bypass nothing."
  }
  assert {
    condition     = length(azurerm_storage_account.this.network_rules[0].virtual_network_subnet_ids) == 2
    error_message = "the rules admit exactly the given subnets."
  }
}

run "rules_need_public_access" {
  command = plan

  variables {
    network_rules = {
      virtual_network_subnet_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/aks"]
    }
  }

  expect_failures = [azurerm_storage_account.this]
}
