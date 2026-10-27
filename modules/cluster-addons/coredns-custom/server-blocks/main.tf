# Pure mapping (no provider, no resources): zones -> the data of the AKS
# coredns-custom ConfigMap. AKS imports every "*.server" key as extra CoreDNS
# server blocks. No zones render no data at all.
locals {
  blocks = [for z in var.zones : "${z}:53 {\n  errors\n  cache 30\n  forward . ${var.forwarder}\n}\n"]
}

output "data" {
  description = "ConfigMap data: one key, azure-private-zones.server, holding one server block per zone; empty when there are no zones."
  value       = length(local.blocks) == 0 ? {} : { "azure-private-zones.server" = join("\n", local.blocks) }
}
