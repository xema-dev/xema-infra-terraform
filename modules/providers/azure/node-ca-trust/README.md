# providers/azure/node-ca-trust

A helper with no provider and no resources, used by [`cluster`](../cluster). It validates the private CA certificates an AKS cluster's nodes trust, and maps them to `azurerm_kubernetes_cluster.custom_ca_trust_certificates_base64`. It is separate so its rules run under `terraform test` with no provider, on Terraform 1.6 and OpenTofu.

- At most 10 certificates and 35 KB in total (AKS limits).
- Each entry is exactly one PEM certificate with LF line endings. Bundles, keys and CRLF are refused at plan.
- Each entry is trimmed and base64-encoded. An empty list maps to `null`, so a cluster without custom CAs plans no change.

Tests: [`tests/ca_trust.tftest.hcl`](tests/ca_trust.tftest.hcl).
