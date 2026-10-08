variables {
  secret_stores = {
    alpha = {
      namespaces   = ["alpha", "alpha-infra"]
      key_vault_id = "/subscriptions/s/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/alpha"
      vault_uri    = "https://alpha.vault.azure.net/"
    }
    beta = {
      namespaces   = ["beta"]
      key_vault_id = "/subscriptions/s/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/beta"
      vault_uri    = "https://beta.vault.azure.net/"
    }
  }
}

run "valid_map" {
  command = plan
  assert {
    condition     = length(output.stores) == 3 && contains(keys(output.stores), "alpha/alpha-infra") && output.stores["beta/beta"].vault_uri == "https://beta.vault.azure.net/"
    error_message = "one store per (boundary, namespace), each on its own vault."
  }
}

run "empty_map_is_valid" {
  command = plan
  variables {
    secret_stores = {}
  }
  assert {
    condition     = length(output.stores) == 0
    error_message = "no boundaries, no stores."
  }
}

run "duplicate_namespace_refused" {
  command = plan
  variables {
    secret_stores = {
      alpha = {
        namespaces   = ["shared"]
        key_vault_id = "/vaults/alpha"
        vault_uri    = "https://alpha.vault.azure.net/"
      }
      beta = {
        namespaces   = ["shared"]
        key_vault_id = "/vaults/beta"
        vault_uri    = "https://beta.vault.azure.net/"
      }
    }
  }
  expect_failures = [var.secret_stores]
}

run "shared_vault_refused" {
  command = plan
  variables {
    secret_stores = {
      alpha = {
        namespaces   = ["alpha"]
        key_vault_id = "/vaults/one"
        vault_uri    = "https://one.vault.azure.net/"
      }
      beta = {
        namespaces   = ["beta"]
        key_vault_id = "/vaults/ONE"
        vault_uri    = "https://one.vault.azure.net/"
      }
    }
  }
  expect_failures = [var.secret_stores]
}

run "empty_namespaces_refused" {
  command = plan
  variables {
    secret_stores = {
      alpha = {
        namespaces   = []
        key_vault_id = "/vaults/alpha"
        vault_uri    = "https://alpha.vault.azure.net/"
      }
    }
  }
  expect_failures = [var.secret_stores]
}
