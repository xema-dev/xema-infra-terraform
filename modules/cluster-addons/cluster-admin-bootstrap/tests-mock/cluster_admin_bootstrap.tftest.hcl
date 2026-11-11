# Needs mock_provider (Terraform 1.7+ / OpenTofu 1.8+): run as
#   terraform test -test-directory=tests-mock
mock_provider "helm" {}
mock_provider "azapi" {}
mock_provider "archive" {}

variables {
  chart_path         = "./tests-mock/fixtures/chart"
  chart_archive_path = "./tests-mock/fixtures/chart.zip"
  aks_cluster_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ContainerService/managedClusters/aks"
}

run "apply_via_is_required" {
  command         = plan
  expect_failures = [var.apply_via]
  variables {
    apply_via = "none"
  }
}

run "in_vnet_is_one_helm_release" {
  command = plan
  variables {
    apply_via = "in-vnet"
  }
  assert {
    condition     = length(helm_release.this) == 1 && helm_release.this[0].take_ownership == true && helm_release.this[0].namespace == "xema-cluster-admin"
    error_message = "one helm_release, take_ownership, in the release namespace."
  }
  assert {
    condition     = length(azapi_resource_action.run_command) == 0
    error_message = "no azapi action in-vnet."
  }
  assert {
    condition     = output.chart_version == "1.2.3" && output.apply_via == "in-vnet"
    error_message = "outputs carry the chart version and mode."
  }
}

run "run_command_is_one_azapi_action" {
  command = apply
  variables {
    apply_via = "run-command"
  }
  override_resource {
    target = azapi_resource_action.run_command
    values = {
      output = { properties = { exitCode = 0, logs = "ok" } }
    }
  }
  assert {
    condition     = length(azapi_resource_action.run_command) == 1 && length(helm_release.this) == 0
    error_message = "one azapi action, no helm_release."
  }
  assert {
    condition     = strcontains(azapi_resource_action.run_command[0].body.command, "--take-ownership")
    error_message = "the command adopts hand-applied objects."
  }
  assert {
    condition     = !strcontains(lower(jsonencode(azapi_resource_action.run_command[0].body.command)), "password") && !strcontains(lower(azapi_resource_action.run_command[0].body.command), "token") && !strcontains(azapi_resource_action.run_command[0].body.command, "--username")
    error_message = "no credential in the command."
  }
}

run "run_command_requires_cluster_id" {
  command         = plan
  expect_failures = [var.aks_cluster_id]
  variables {
    apply_via      = "run-command"
    aks_cluster_id = null
  }
}

run "release_name_with_space_is_refused" {
  command         = plan
  expect_failures = [var.release_name]
  variables {
    apply_via    = "in-vnet"
    release_name = "a b"
  }
}

run "release_name_with_semicolon_is_refused" {
  command         = plan
  expect_failures = [var.release_name]
  variables {
    apply_via    = "in-vnet"
    release_name = "a;rm"
  }
}

run "run_command_nonzero_exit_fails_with_logs" {
  command         = plan
  expect_failures = [azapi_resource_action.run_command]
  variables {
    apply_via = "run-command"
  }
  override_resource {
    target = azapi_resource_action.run_command
    values = {
      output = { properties = { exitCode = 1, logs = "boom" } }
    }
  }
}
