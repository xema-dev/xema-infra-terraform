run "default_is_cilium" {
  command = plan
  assert {
    condition     = output.network_policy == "cilium" && output.network_data_plane == "cilium"
    error_message = "the default must be the Cilium dataplane and policy engine."
  }
}

run "calico_keeps_azure_dataplane" {
  command = plan
  variables {
    engine = "calico"
  }
  assert {
    condition     = output.network_policy == "calico" && output.network_data_plane == "azure"
    error_message = "calico runs on the Azure dataplane."
  }
}

run "azure_is_refused" {
  command = plan
  variables {
    engine = "azure"
  }
  expect_failures = [var.engine]
}

run "none_is_refused" {
  command = plan
  variables {
    engine = "none"
  }
  expect_failures = [var.engine]
}

run "unknown_is_refused" {
  command = plan
  variables {
    engine = "weave"
  }
  expect_failures = [var.engine]
}
