variables {
  deployment_name = "acme-dev"
}

run "derives_deterministically" {
  command = plan
  variables {
    boundaries = {
      alpha = {}
      beta  = { vault_name = "custom-beta-vault" }
    }
  }
  assert {
    condition     = output.operator == "acme-dev-kv" && output.boundaries["alpha"] == "acme-dev-alpha-kv" && output.boundaries["beta"] == "custom-beta-vault"
    error_message = "operator <dep>-kv, boundary <dep>-<key>-kv unless overridden."
  }
}

run "no_boundaries_is_valid" {
  command = plan
  assert {
    condition     = length(output.boundaries) == 0 && output.operator == "acme-dev-kv"
    error_message = "no boundaries, only the operator vault."
  }
}

run "too_long_derived_name_refused" {
  command = plan
  variables {
    boundaries = { "a-rather-long-boundary" = {} }
  }
  expect_failures = [terraform_data.guard]
}

run "too_long_derived_name_with_override_accepted" {
  command = plan
  variables {
    boundaries = { "a-rather-long-boundary" = { vault_name = "acme-long-kv" } }
  }
  assert {
    condition     = output.boundaries["a-rather-long-boundary"] == "acme-long-kv"
    error_message = "an explicit name replaces the derived one."
  }
}

run "double_hyphen_refused" {
  command = plan
  variables {
    boundaries = { "a--b" = {} }
  }
  expect_failures = [terraform_data.guard]
}

run "bad_override_charset_refused" {
  command = plan
  variables {
    boundaries = { alpha = { vault_name = "bad_name" } }
  }
  expect_failures = [terraform_data.guard]
}

run "override_starting_with_digit_refused" {
  command = plan
  variables {
    operator_vault_name = "1abc"
  }
  expect_failures = [terraform_data.guard]
}

run "boundary_equal_to_operator_refused" {
  command = plan
  variables {
    boundaries = { alpha = { vault_name = "ACME-DEV-KV" } }
  }
  expect_failures = [terraform_data.guard]
}

run "two_boundaries_same_vault_refused" {
  command = plan
  variables {
    boundaries = {
      alpha = { vault_name = "shared-kv" }
      beta  = { vault_name = "Shared-KV" }
    }
  }
  expect_failures = [terraform_data.guard]
}
