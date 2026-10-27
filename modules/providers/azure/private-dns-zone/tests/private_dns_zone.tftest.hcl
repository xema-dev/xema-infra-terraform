# Provider-free: the rules for the API's private DNS zone, proven at plan on
# Terraform 1.6 and OpenTofu alike.

run "default_is_null" {
  command = plan
  variables {
    private_cluster_enabled = true
  }
  assert {
    condition     = output.private_dns_zone_id == null
    error_message = "unset must map to null, so existing clusters plan no change."
  }
}

run "none_with_private_and_public_fqdn_reaches_the_cluster" {
  command = plan
  variables {
    private_cluster_enabled = true
    public_fqdn_enabled     = true
    private_dns_zone_id     = "None"
  }
  assert {
    condition     = output.private_dns_zone_id == "None"
    error_message = "\"None\" must reach the cluster resource unchanged."
  }
}

run "zone_resource_id_reaches_the_cluster" {
  command = plan
  variables {
    private_cluster_enabled = true
    private_dns_zone_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/privateDnsZones/privatelink.germanywestcentral.azmk8s.io"
  }
  assert {
    condition     = output.private_dns_zone_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/privateDnsZones/privatelink.germanywestcentral.azmk8s.io"
    error_message = "a zone resource id must reach the cluster resource unchanged."
  }
}

run "public_cluster_maps_to_null" {
  command = plan
  variables {
    private_dns_zone_id = "System"
  }
  assert {
    condition     = output.private_dns_zone_id == null
    error_message = "a public cluster has no private DNS zone."
  }
}

run "none_without_private_cluster_is_refused" {
  command = plan
  variables {
    private_dns_zone_id = "None"
    public_fqdn_enabled = true
  }
  expect_failures = [output.private_dns_zone_id]
}

run "none_without_public_fqdn_is_refused" {
  command = plan
  variables {
    private_cluster_enabled = true
    private_dns_zone_id     = "None"
  }
  expect_failures = [output.private_dns_zone_id]
}

run "garbage_is_refused" {
  command = plan
  variables {
    private_cluster_enabled = true
    private_dns_zone_id     = "none"
  }
  expect_failures = [var.private_dns_zone_id]
}
