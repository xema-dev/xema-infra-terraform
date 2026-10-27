# Provider-free: the CoreDNS server blocks rendered for the forwarded zones.

run "no_zones_render_no_data" {
  command = plan
  assert {
    condition     = output.data == {}
    error_message = "an empty zone list must render no data, so no ConfigMap is created."
  }
}

run "one_server_block_per_zone" {
  command = plan
  variables {
    zones = ["privatelink.vaultcore.azure.net", "privatelink.postgres.database.azure.com", "privatelink.blob.core.windows.net"]
  }
  assert {
    condition     = length(regexall("(?m)^[a-z.]+:53 \\{$", output.data["azure-private-zones.server"])) == 3
    error_message = "there must be exactly one server block per zone."
  }
  assert {
    condition     = length(regexall("forward \\. 168\\.63\\.129\\.16", output.data["azure-private-zones.server"])) == 3
    error_message = "every block must forward to Azure DNS 168.63.129.16."
  }
  assert {
    condition     = strcontains(output.data["azure-private-zones.server"], "privatelink.postgres.database.azure.com:53 {\n  errors\n  cache 30\n  forward . 168.63.129.16\n}\n")
    error_message = "a block must read: zone:53 { errors, cache 30, forward . 168.63.129.16 }."
  }
}

run "zone_without_privatelink_prefix_is_allowed" {
  command = plan
  variables {
    zones = ["corp.example.com"]
  }
  assert {
    condition     = strcontains(output.data["azure-private-zones.server"], "corp.example.com:53 {")
    error_message = "any DNS name is a valid zone."
  }
}

run "invalid_zone_is_refused" {
  command = plan
  variables {
    zones = ["Not A Zone"]
  }
  expect_failures = [var.zones]
}

run "trailing_dot_is_refused" {
  command = plan
  variables {
    zones = ["privatelink.vaultcore.azure.net."]
  }
  expect_failures = [var.zones]
}

run "duplicate_zone_is_refused" {
  command = plan
  variables {
    zones = ["a.example.com", "a.example.com"]
  }
  expect_failures = [var.zones]
}
