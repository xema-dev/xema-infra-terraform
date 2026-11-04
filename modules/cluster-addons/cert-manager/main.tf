# The one cert-manager definition of this repository: chart, version pin and values. Both the
# standalone install of a stack and the gateway-tls module call it, and each decides on its own
# side that a given cluster gets exactly one instance.
locals {
  values = yamlencode(merge(
    {
      # CRDs are installed with the chart and kept when it is uninstalled, so no Certificate is lost.
      crds = { enabled = true, keep = true }
      serviceAccount = {
        name = var.service_account_name
      }
      config = {
        apiVersion       = "controller.config.cert-manager.io/v1alpha1"
        kind             = "ControllerConfiguration"
        enableGatewayAPI = var.gateway_api
      }
    },
    var.workload_identity ? {
      podLabels = { "azure.workload.identity/use" = "true" }
    } : {},
  ))
}

resource "helm_release" "this" {
  name             = "cert-manager"
  repository       = var.chart_repository
  chart            = "cert-manager"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true

  values = concat([local.values], var.images_values, var.values)
}
