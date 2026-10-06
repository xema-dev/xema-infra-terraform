run "nothing_enabled_is_empty" {
  command = plan
  assert {
    condition     = length(output.assigned_role_names) == 0
    error_message = "no module enabled must assign no role."
  }
}

run "everything_enabled_is_sorted_and_distinct" {
  command = plan
  variables {
    enable_cluster            = true
    enable_container_registry = true
    enable_dns                = true
    enable_secrets_backend    = true
  }
  assert {
    condition = jsonencode(output.assigned_role_names) == jsonencode([
      "AcrPull",
      "DNS Zone Contributor",
      "Key Vault Secrets Officer",
      "Key Vault Secrets User",
      "Network Contributor",
    ])
    error_message = "the full set must be sorted and de-duplicated."
  }
}

run "only_enabled_modules_count" {
  command = plan
  variables {
    enable_container_registry = true
  }
  assert {
    condition     = jsonencode(output.assigned_role_names) == jsonencode(["AcrPull"])
    error_message = "only the enabled module's roles are listed."
  }
}

run "no_duplicates_when_modules_share_a_role" {
  command = plan
  variables {
    enable_cluster = true
  }
  assert {
    condition     = length(output.assigned_role_names) == length(distinct(output.assigned_role_names))
    error_message = "duplicates must be removed."
  }
}
