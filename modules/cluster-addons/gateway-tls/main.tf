# The HTTPS listeners, their Secrets and the Certificates of the managed ones, validated
# without a provider (./listeners/tests). Only with NGINX Gateway Fabric: a customer-managed
# Gateway's listeners and certificates are the customer's.
module "listeners" {
  source = "./listeners"
  count  = local.ngf ? 1 : 0

  listeners           = var.listeners
  gateway_name        = var.gateway_name
  cluster_issuer_name = var.cluster_issuer_name
  tls_solver          = var.tls_solver
  dns01_zones         = try(var.dns01_azure.hosted_zone_names, [])
}

locals {
  dns01 = var.tls_solver == "dns01-azure"
  ngf   = var.gateway_implementation == "nginx-gateway-fabric"

  # The port-80 listener's name: the contract the HTTP-01 solver route and the redirect share.
  http_section_name = "http"

  listeners    = local.ngf ? module.listeners[0].listeners : {}
  certificates = local.ngf ? module.listeners[0].certificates : {}

  gateway_ref = local.ngf ? {
    name                = var.gateway_name
    namespace           = var.gateway_namespace
    http_section_name   = local.http_section_name
    https_section_names = sort(keys(local.listeners))
    } : {
    name                = try(var.customer_gateway.name, null)
    namespace           = try(var.customer_gateway.namespace, null)
    http_section_name   = try(var.customer_gateway.http_section_name, null)
    https_section_names = sort(tolist(try(var.customer_gateway.https_section_names, [])))
  }

  # The Gateway, NginxProxy and ClientSettingsPolicy live in the Gateway's namespace;
  # a customer-managed Gateway is not ours, so the issuer chart sits with cert-manager.
  config_namespace = local.ngf ? var.gateway_namespace : var.cert_manager_namespace

  ngf_values = yamlencode({
    nginxGateway = {
      gatewayClassName = var.gateway_class_name
    }
  })

  # enableGatewayAPI turns on cert-manager's HTTP-01 gatewayHTTPRoute solver. The Gateway carries no
  # cert-manager.io/cluster-issuer annotation, so the gateway-shim issues nothing: each managed
  # listener gets an explicit Certificate, and a customer_supplied listener none.
  # With dns01-azure the controller pod must carry the workload-identity label so the Azure
  # webhook injects the federated token cert-manager exchanges.
  cert_manager_values = yamlencode(merge(
    {
      crds = { enabled = true, keep = true }
      serviceAccount = {
        name = var.cert_manager_service_account_name
      }
      config = {
        apiVersion       = "controller.config.cert-manager.io/v1alpha1"
        kind             = "ControllerConfiguration"
        enableGatewayAPI = true
      }
    },
    local.dns01 ? {
      podLabels = { "azure.workload.identity/use" = "true" }
    } : {},
  ))

  cluster_config_values = yamlencode({
    clusterIssuer = {
      name   = var.cluster_issuer_name
      email  = var.acme_email
      server = var.acme_server
      solver = var.tls_solver
      httpParentRef = {
        name        = local.gateway_ref.name
        namespace   = local.gateway_ref.namespace
        sectionName = local.gateway_ref.http_section_name
      }
      dns01Azure = local.dns01 ? {
        subscriptionID    = var.dns01_azure.subscription_id
        resourceGroupName = var.dns01_azure.resource_group_name
        hostedZoneNames   = sort(tolist(var.dns01_azure.hosted_zone_names))
        clientID          = var.dns01_azure.client_id
        environment       = var.dns01_azure.environment
      } : null
    }
    gateway = local.ngf ? {
      name            = var.gateway_name
      namespace       = var.gateway_namespace
      className       = var.gateway_class_name
      httpSectionName = local.http_section_name
      listeners = [for k in sort(keys(local.listeners)) : {
        name       = k
        hostname   = local.listeners[k].hostname
        secretName = local.listeners[k].secret_name
      }]
      certificates = [for k in sort(keys(local.certificates)) : {
        name       = local.certificates[k].name
        dnsNames   = local.certificates[k].dns_names
        secretName = local.certificates[k].secret_name
        issuerName = local.certificates[k].issuer_name
      }]
      routeNamespaces           = sort(tolist(var.route_namespaces))
      infrastructureAnnotations = var.gateway_infrastructure_annotations
      maxRequestBody            = "${var.max_request_body_mib}m"
      dataPlane = {
        serviceType           = var.data_plane_service_type
        externalTrafficPolicy = var.data_plane_external_traffic_policy
        loadBalancerIP        = var.data_plane_load_balancer_ip
        nodePorts = [for p in var.data_plane_node_ports : {
          port         = p.port
          listenerPort = p.listener_port
        }]
      }
    } : null
  })
}

# The Gateway API standard-channel CRDs, pinned by the vendored bundle (charts/gateway-api-crds,
# appVersion = the upstream release). Installed only with NGINX Gateway Fabric: a customer-managed
# Gateway means the customer's own IaC owns the CRDs, and a second owner would fight over them.
resource "helm_release" "gateway_api_crds" {
  count = local.ngf ? 1 : 0

  name             = "gateway-api-crds"
  chart            = "${path.module}/charts/gateway-api-crds"
  namespace        = var.gateway_api_crds_namespace
  create_namespace = true
}

resource "helm_release" "nginx_gateway_fabric" {
  count = local.ngf ? 1 : 0

  name             = var.ngf_release_name
  repository       = "oci://ghcr.io/nginx/charts"
  chart            = "nginx-gateway-fabric"
  version          = var.ngf_chart_version
  namespace        = var.ngf_namespace
  create_namespace = true

  values = concat([local.ngf_values], var.ngf_values)

  depends_on = [helm_release.gateway_api_crds]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version
  namespace        = var.cert_manager_namespace
  create_namespace = true

  values = concat([local.cert_manager_values], var.cert_manager_values)

  # cert-manager's controller fails to start with enableGatewayAPI when the Gateway API CRDs are absent.
  depends_on = [helm_release.gateway_api_crds]

  lifecycle {
    precondition {
      condition     = !local.dns01 || var.dns01_azure != null
      error_message = "tls_solver = \"dns01-azure\" requires dns01_azure (subscription, resource group, zone, client id)."
    }
    precondition {
      condition     = local.ngf || var.customer_gateway != null
      error_message = "gateway_implementation = \"customer-managed\" requires customer_gateway (the existing Gateway's name, namespace and listener names)."
    }
    precondition {
      condition     = !local.ngf || var.customer_gateway == null
      error_message = "customer_gateway is only meaningful with gateway_implementation = \"customer-managed\"."
    }
    precondition {
      condition     = !local.ngf || length(var.route_namespaces) > 0
      error_message = "gateway_implementation = \"nginx-gateway-fabric\" requires a non-empty route_namespaces: no namespace may attach routes by default."
    }
    precondition {
      condition     = local.ngf || length(var.listeners) == 0
      error_message = "listeners are only meaningful with gateway_implementation = \"nginx-gateway-fabric\": a customer-managed Gateway's listeners and certificates are the customer's (name them in customer_gateway.https_section_names)."
    }
  }
}

# The ClusterIssuer, Gateway, Certificates, NginxProxy and ClientSettingsPolicy are custom resources whose CRDs do
# not exist until cert-manager and NGINX Gateway Fabric are installed, so they ship as a tiny LOCAL
# chart rather than kubernetes_manifest — which needs the CRD at PLAN time and therefore cannot
# survive a first apply on a fresh cluster. Helm validates them at install, when the CRDs and their
# webhooks are up.
resource "helm_release" "cluster_config" {
  name             = "gateway-tls-cluster-config"
  chart            = "${path.module}/charts/cluster-config"
  namespace        = local.config_namespace
  create_namespace = true

  values = [local.cluster_config_values]

  depends_on = [helm_release.cert_manager, helm_release.nginx_gateway_fabric]
}
