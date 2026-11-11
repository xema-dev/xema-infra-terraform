# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# Every role the module creates carries the installation's ownership marker as
# its comment (`xema installation import` refuses an unmarked role as foreign),
# with the marker text taken as given, and a marker outside the grammar is
# refused before anything is planned.

mock_provider "postgresql" {}
mock_provider "random" {}

variables {
  connecting_role     = "admin"
  connecting_password = "not-a-real-password"
  sql_connection      = { host = "db.internal.example" }
  ownership_marker    = "xema-deploy:managed deployment=acme-dev"
  databases           = ["acme_dev_app"]
  roles               = ["acme_dev", "acme_dev_provisioner"]
  database_owners     = { acme_dev_app = "acme_dev" }
  connect_grants      = { acme_dev = ["acme_dev_app"], acme_dev_provisioner = ["acme_dev_app"] }
  role_options        = { acme_dev_provisioner = { create_database = true } }
}

run "every_role_is_commented_with_the_marker" {
  command = plan

  assert {
    condition     = toset(keys(terraform_data.role_marker)) == toset(["acme_dev", "acme_dev_provisioner"])
    error_message = "every managed role must get a marker step, and nothing else."
  }

  assert {
    condition = alltrue([
      for role, marker in terraform_data.role_marker :
      marker.input.role == role && marker.input.comment == "xema-deploy:managed deployment=acme-dev"
    ])
    error_message = "each role's comment must be the given ownership_marker, verbatim."
  }

  assert {
    condition = (
      terraform_data.role_marker["acme_dev"].input.sql == "COMMENT ON ROLE \"acme_dev\" IS 'xema-deploy:managed deployment=acme-dev'"
      && terraform_data.role_marker["acme_dev_provisioner"].input.sql == "COMMENT ON ROLE \"acme_dev_provisioner\" IS 'xema-deploy:managed deployment=acme-dev'"
    )
    error_message = "the statement must be COMMENT ON ROLE <role> IS '<ownership_marker>'."
  }
}

run "a_marker_outside_the_grammar_is_refused" {
  command = plan

  variables {
    ownership_marker = "xema-deploy:managed deployment=acme'; DROP ROLE admin; --"
  }

  expect_failures = [var.ownership_marker]
}

run "an_empty_marker_is_refused" {
  command = plan

  variables {
    ownership_marker = "xema-deploy:managed deployment="
  }

  expect_failures = [var.ownership_marker]
}
