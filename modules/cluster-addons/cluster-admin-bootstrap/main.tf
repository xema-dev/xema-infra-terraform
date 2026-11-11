locals {
  in_vnet     = var.apply_via == "in-vnet"
  run_command = var.apply_via == "run-command"
  chart       = yamldecode(file("${var.chart_path}/Chart.yaml"))

  # --take-ownership adopts objects hand-applied earlier. No registry login, no
  # values, no secret: the chart is the zip itself, extracted into the working
  # directory of the run-command pod.
  archive_path = coalesce(var.chart_archive_path, "${path.module}/.chart.zip")

  helm_command = "helm upgrade --install ${var.release_name} . --namespace ${var.release_namespace} --create-namespace --take-ownership --wait"
}

resource "helm_release" "this" {
  count = local.in_vnet ? 1 : 0

  name             = var.release_name
  chart            = var.chart_path
  namespace        = var.release_namespace
  create_namespace = true
  take_ownership   = true
  atomic           = false
  wait             = true
}

# Zips ONLY the chart directory; nothing else is sent to the cluster.
data "archive_file" "chart" {
  count = local.run_command ? 1 : 0

  type        = "zip"
  source_dir  = var.chart_path
  output_path = local.archive_path

  # A symlink in the chart dir could pull files from outside it into the zip.
  exclude_symlink_directories = true
}

# azapi_resource_action has no triggers_replace; replacing it on a chart change
# is what re-runs the command.
resource "terraform_data" "chart_hash" {
  count = local.run_command ? 1 : 0

  input = data.archive_file.chart[0].output_sha256
}

resource "azapi_resource_action" "run_command" {
  count = local.run_command ? 1 : 0

  type        = "Microsoft.ContainerService/managedClusters@2024-09-01"
  resource_id = var.aks_cluster_id
  action      = "runCommand"
  method      = "POST"

  body = {
    command = local.helm_command
    context = filebase64(data.archive_file.chart[0].output_path)
  }

  # The admin's Entra token for the AKS server app: with local accounts off, the
  # run-command pod has no credential without it. Write-only: never in plan or state.
  sensitive_body = {
    clusterToken = var.cluster_token
  }

  response_export_values = ["properties.exitCode", "properties.logs"]

  lifecycle {
    replace_triggered_by = [terraform_data.chart_hash[0]]

    postcondition {
      condition     = tostring(self.output.properties.exitCode) == "0"
      error_message = "helm run-command failed with exit code ${tostring(self.output.properties.exitCode)}: ${self.output.properties.logs}"
    }
  }
}
