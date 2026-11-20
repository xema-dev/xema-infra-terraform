# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# cors_rules is opt-in: none by default; each rule maps onto a cors_rule block in
# blob_properties. Azure requires non-empty allowed/exposed headers.

mock_provider "azurerm" {}

variables {
  name                = "satest"
  region              = "westeurope"
  resource_group_name = "rg"
}

run "default_renders_no_cors" {
  command = plan

  assert {
    condition     = length(azurerm_storage_account.this.blob_properties[0].cors_rule) == 0
    error_message = "without cors_rules no cors_rule block is rendered."
  }
}

run "rule_maps_every_field" {
  command = plan

  variables {
    cors_rules = [{
      allowed_origins = ["https://app.example.com", "http://localhost:3000"]
      allowed_methods = ["GET", "PUT"]
      allowed_headers = ["*"]
      exposed_headers = ["ETag"]
      max_age         = 3600
    }]
  }

  assert {
    condition = (
      length(azurerm_storage_account.this.blob_properties[0].cors_rule) == 1
      && toset(azurerm_storage_account.this.blob_properties[0].cors_rule[0].allowed_origins) == toset(["https://app.example.com", "http://localhost:3000"])
      && toset(azurerm_storage_account.this.blob_properties[0].cors_rule[0].allowed_methods) == toset(["GET", "PUT"])
      && azurerm_storage_account.this.blob_properties[0].cors_rule[0].allowed_headers == tolist(["*"])
      && azurerm_storage_account.this.blob_properties[0].cors_rule[0].exposed_headers == tolist(["ETag"])
      && azurerm_storage_account.this.blob_properties[0].cors_rule[0].max_age_in_seconds == 3600
    )
    error_message = "the rule maps origins, methods, headers, exposed headers and max age."
  }
}

run "origin_with_path_fails" {
  command = plan

  variables {
    cors_rules = [{
      allowed_origins = ["https://app.example.com/path"]
      allowed_methods = ["GET"]
      allowed_headers = ["*"]
      exposed_headers = ["ETag"]
    }]
  }

  expect_failures = [var.cors_rules]
}

run "method_outside_set_fails" {
  command = plan

  variables {
    cors_rules = [{
      allowed_origins = ["*"]
      allowed_methods = ["TRACE"]
      allowed_headers = ["*"]
      exposed_headers = ["ETag"]
    }]
  }

  expect_failures = [var.cors_rules]
}

run "empty_headers_fail" {
  command = plan

  variables {
    cors_rules = [{
      allowed_origins = ["*"]
      allowed_methods = ["GET"]
    }]
  }

  expect_failures = [var.cors_rules]
}

run "sixth_rule_fails" {
  command = plan

  variables {
    cors_rules = [for i in range(6) : {
      allowed_origins = ["https://app${i}.example.com"]
      allowed_methods = ["GET"]
      allowed_headers = ["*"]
      exposed_headers = ["ETag"]
    }]
  }

  expect_failures = [var.cors_rules]
}
