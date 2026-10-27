# providers/azure/private-dns-zone

A helper with no provider and no resources, used by [`cluster`](../cluster). It validates the API's private DNS zone setting and maps it to `azurerm_kubernetes_cluster.private_dns_zone_id`. It is separate so its rules run under `terraform test` with no provider, on Terraform 1.6 and OpenTofu.

- `private_dns_zone_id` is null, `"System"`, `"None"` or the resource id of an Azure private DNS zone. Anything else is refused at plan.
- `"None"` needs a private cluster with the public FQDN enabled. Without a private zone the nodes reach the API only through its public name.
- A public cluster maps to null, and so does an unset value, so an existing cluster plans no change.

Tests: [`tests/private_dns_zone.tftest.hcl`](tests/private_dns_zone.tftest.hcl).
