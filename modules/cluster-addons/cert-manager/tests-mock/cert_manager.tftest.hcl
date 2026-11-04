# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
mock_provider "helm" {}

run "defaults_install_crds_and_leave_gateway_api_off" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.this.values[0]).crds == { enabled = true, keep = true }
    error_message = "CRDs are installed and kept."
  }
  assert {
    condition     = yamldecode(helm_release.this.values[0]).config.enableGatewayAPI == false
    error_message = "Gateway API support is off by default."
  }
  assert {
    condition     = !can(yamldecode(helm_release.this.values[0]).podLabels)
    error_message = "no workload-identity label by default."
  }
  assert {
    condition     = helm_release.this.version == "v1.21.2" && helm_release.this.namespace == "cert-manager"
    error_message = "the chart pin and namespace default."
  }
}

run "gateway_api_and_workload_identity_render" {
  command = plan

  variables {
    gateway_api       = true
    workload_identity = true
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).config.enableGatewayAPI == true && yamldecode(helm_release.this.values[0]).podLabels["azure.workload.identity/use"] == "true"
    error_message = "gateway_api and workload_identity render into the values."
  }
}
