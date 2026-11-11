# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# role_ownership = "unowned" is threaded to modules/postgres-tenancy: no marker,
# no stamp. An invalid value is refused here.

mock_provider "azurerm" {
  mock_resource "azurerm_postgresql_flexible_server" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/pg"
    }
  }
}
mock_provider "postgresql" {}
mock_provider "random" {}

variables {
  name           = "pg-test"
  region         = "westeurope"
  engine_version = "16"
  size           = "B_Standard_B2s"
  network_access = "public"
  roles          = ["temporal"]
  databases      = ["temporal"]
}

run "unowned_plans_without_a_marker" {
  command = plan

  variables {
    role_ownership   = "unowned"
    ownership_marker = null
  }

  assert {
    condition     = length(module.tenancy[0].role_ownership_markers) == 0
    error_message = "unowned roles must carry no marker."
  }
}

run "installation_with_a_marker_stamps_every_role" {
  command = plan

  variables {
    ownership_marker = "xema-deploy:managed deployment=acme-dev"
  }

  assert {
    condition     = keys(module.tenancy[0].role_ownership_markers) == ["temporal"]
    error_message = "an installation's role must be stamped."
  }
}

run "an_unknown_role_ownership_is_refused" {
  command = plan

  variables {
    role_ownership = "shared"
  }

  expect_failures = [var.role_ownership]
}
