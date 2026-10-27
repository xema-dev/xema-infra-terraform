# The rules and the rendering live in a provider-free submodule with tests.
module "server_blocks" {
  source    = "./server-blocks"
  zones     = var.zones
  forwarder = var.forwarder
}

# AKS owns the kube-system/coredns-custom ConfigMap: it pre-creates it empty and
# keeps it present. This module owns only its data key, so it never collides with
# that object and destroy removes just the key. CoreDNS picks up the change as
# Microsoft documents: after a change, restart it with
# `kubectl -n kube-system rollout restart deployment coredns` (not automated here).
resource "kubernetes_config_map_v1_data" "coredns_custom" {
  count = length(module.server_blocks.data) == 0 ? 0 : 1

  metadata {
    name      = "coredns-custom"
    namespace = "kube-system"
  }

  data          = module.server_blocks.data
  force         = true
  field_manager = "xema-infra-terraform"
}
