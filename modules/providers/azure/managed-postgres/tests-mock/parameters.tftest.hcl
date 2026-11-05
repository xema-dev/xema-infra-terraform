# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock

mock_provider "azurerm" {
  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg"
    }
  }
  mock_resource "azurerm_postgresql_flexible_server" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/pg"
    }
  }
}

variables {
  name           = "pg-test"
  region         = "westeurope"
  engine_version = "16"
  size           = "B_Standard_B2s"
  network_access = "public"
}

run "no_parameters_render_nothing" {
  command = plan

  assert {
    condition     = length(azurerm_postgresql_flexible_server_configuration.parameters) == 0
    error_message = "an empty map must create no server configuration"
  }
}

run "one_parameter_renders_one_configuration" {
  command = plan

  variables {
    parameters = { max_connections = "429" }
  }

  assert {
    condition     = length(azurerm_postgresql_flexible_server_configuration.parameters) == 1
    error_message = "one entry must create one server configuration"
  }

  assert {
    condition     = azurerm_postgresql_flexible_server_configuration.parameters["max_connections"].name == "max_connections"
    error_message = "the configuration must carry the parameter name"
  }

  assert {
    condition     = azurerm_postgresql_flexible_server_configuration.parameters["max_connections"].value == "429"
    error_message = "the configuration must carry the parameter value"
  }
}

run "extensions_parameter_is_refused" {
  command = plan

  variables {
    parameters = { "azure.extensions" = "pg_trgm" }
  }

  expect_failures = [var.parameters]
}

run "malformed_name_is_refused" {
  command = plan

  variables {
    parameters = { "Max Connections" = "429" }
  }

  expect_failures = [var.parameters]
}
