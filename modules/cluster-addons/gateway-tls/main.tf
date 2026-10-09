# Every input-combination rule, the HTTPS listeners with their Secrets, the Certificates of the
# managed ones, and whether an issuer is installed at all — validated without a provider
# (./tls-plan/tests).
module "tls_plan" {
  source = "./tls-plan"

  gateway_implementation               = var.gateway_implementation
  listeners                            = var.listeners
  gateway_name                         = var.gateway_name
  route_namespaces                     = var.route_namespaces
  customer_gateway_https_section_names = try(var.customer_gateway.https_section_names, null)
  cluster_issuer_name                  = var.cluster_issuer_name
  acme_email                           = var.acme_email
  tls_solver                           = var.tls_solver
  dns01_zones                          = try(var.dns01_azure.hosted_zone_names, [])
}

locals {
  dns01 = var.tls_solver == "dns01-azure"
  ngf   = var.gateway_implementation == "nginx-gateway-fabric"

  # The port-80 listener's name: the contract the HTTP-01 solver route and the redirect share.
  http_section_name = "http"

  listeners    = module.tls_plan.listeners
  certificates = module.tls_plan.certificates
  # cert-manager and the ACME ClusterIssuer: only when something is issued (tls-plan decides).
  issuer = module.tls_plan.issuer

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

  # The Gateway, its Certificates, NginxProxy and ClientSettingsPolicy live in the Gateway's
  # namespace; a customer-managed Gateway is not ours, so the issuer chart sits with cert-manager.
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
    clusterIssuer = local.issuer ? {
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
    } : null
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

# cert-manager is installed only with an issuer: with every listener customer_supplied nothing in
# this module (or anywhere else in this repository) creates a cert-manager resource.
resource "helm_release" "cert_manager" {
  count = local.issuer ? 1 : 0

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version
  namespace        = var.cert_manager_namespace
  create_namespace = true

  values = concat([local.cert_manager_values], var.cert_manager_values)

  # cert-manager's controller fails to start with enableGatewayAPI when the Gateway API CRDs are absent.
  depends_on = [helm_release.gateway_api_crds]
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
