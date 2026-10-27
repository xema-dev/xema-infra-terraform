# The rules and the rendering live in a provider-free submodule with tests.
module "server_blocks" {
  source    = "./server-blocks"
  zones     = var.zones
  forwarder = var.forwarder
}

# AKS reads the coredns-custom ConfigMap in kube-system and adds every "*.server"
# key to CoreDNS (reloaded within about a minute; no restart needed).
resource "kubernetes_config_map_v1" "coredns_custom" {
  count = length(module.server_blocks.data) == 0 ? 0 : 1

  metadata {
    name      = "coredns-custom"
    namespace = "kube-system"
  }

  data = module.server_blocks.data
}
