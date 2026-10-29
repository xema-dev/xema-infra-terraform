# Provider-free: the version, channel and maintenance-window rules of the AKS cluster, proven at
# plan on Terraform 1.6 and OpenTofu alike.

variables {
  kubernetes_version = "1.34"
}

run "defaults_leave_everything_to_azure" {
  command = plan
  assert {
    condition     = output.automatic_upgrade_channel == null && output.node_os_upgrade_channel == null
    error_message = "unset channels must stay null so Azure's defaults apply and existing callers plan no change."
  }
  assert {
    condition     = length(output.maintenance_window_auto_upgrade) == 0 && length(output.maintenance_window_node_os) == 0
    error_message = "no maintenance window unless asked."
  }
  assert {
    condition     = output.kubernetes_version == "1.34"
    error_message = "the version must reach the cluster as given."
  }
}

run "channels_and_windows_reach_the_cluster" {
  command = plan
  variables {
    automatic_upgrade_channel = "patch"
    node_os_upgrade_channel   = "SecurityPatch"
    maintenance_window_auto_upgrade = {
      frequency   = "Weekly"
      interval    = 1
      duration    = 4
      day_of_week = "Sunday"
      start_time  = "02:00"
    }
    maintenance_window_node_os = {
      frequency  = "Daily"
      interval   = 1
      duration   = 6
      start_time = "03:00"
      not_allowed = [{
        start = "2026-12-24T00:00:00Z"
        end   = "2026-12-27T00:00:00Z"
      }]
    }
  }
  assert {
    condition     = output.automatic_upgrade_channel == "patch" && output.node_os_upgrade_channel == "SecurityPatch"
    error_message = "channels must reach the cluster unchanged."
  }
  assert {
    condition     = length(output.maintenance_window_auto_upgrade) == 1 && output.maintenance_window_auto_upgrade[0].day_of_week == "Sunday"
    error_message = "the auto-upgrade window must reach the cluster."
  }
  assert {
    condition     = length(output.maintenance_window_node_os) == 1 && length(output.maintenance_window_node_os[0].not_allowed) == 1
    error_message = "the node OS window and its blackout must reach the cluster."
  }
}

run "full_version_is_accepted" {
  command = plan
  variables {
    kubernetes_version = "1.34.12"
  }
  assert {
    condition     = output.kubernetes_version == "1.34.12"
    error_message = "a full version is valid."
  }
}

run "version_prefix_with_trailing_dot_is_refused" {
  command = plan
  variables {
    kubernetes_version = "1.34."
  }
  expect_failures = [var.kubernetes_version]
}

run "unknown_upgrade_channel_is_refused" {
  command = plan
  variables {
    automatic_upgrade_channel = "none"
  }
  expect_failures = [var.automatic_upgrade_channel]
}

run "unknown_node_os_channel_is_refused" {
  command = plan
  variables {
    node_os_upgrade_channel = "Patch"
  }
  expect_failures = [var.node_os_upgrade_channel]
}

run "weekly_window_needs_a_day" {
  command = plan
  variables {
    maintenance_window_node_os = {
      frequency = "Weekly"
      interval  = 1
      duration  = 4
    }
  }
  expect_failures = [output.maintenance_window_node_os]
}

run "short_window_is_refused" {
  command = plan
  variables {
    maintenance_window_auto_upgrade = {
      frequency = "Daily"
      interval  = 1
      duration  = 2
    }
  }
  expect_failures = [output.maintenance_window_auto_upgrade]
}

run "relative_monthly_window_needs_a_week_index" {
  command = plan
  variables {
    maintenance_window_auto_upgrade = {
      frequency   = "RelativeMonthly"
      interval    = 1
      duration    = 4
      day_of_week = "Monday"
    }
  }
  expect_failures = [output.maintenance_window_auto_upgrade]
}

run "unknown_frequency_is_refused" {
  command = plan
  variables {
    maintenance_window_node_os = {
      frequency = "Hourly"
      interval  = 1
      duration  = 4
    }
  }
  expect_failures = [output.maintenance_window_node_os]
}
