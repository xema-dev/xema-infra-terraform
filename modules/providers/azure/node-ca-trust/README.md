# providers/azure/node-ca-trust

A helper with no provider and no resources, used by [`cluster`](../cluster). It validates the private CA certificates an AKS cluster's nodes trust, and maps them to `azurerm_kubernetes_cluster.custom_ca_trust_certificates_base64`. It is separate so its rules run under `terraform test` with no provider, on Terraform 1.6 and OpenTofu.

- At most 10 certificates (the AKS API's `maxItems`). At most 35 KB of PEM content, counted as AKS's certificate file: trimmed entries joined by a blank line, against 35000 bytes. AKS documents this limit on the certificate content, not on the base64 field ([custom CA trust](https://learn.microsoft.com/azure/aks/custom-certificate-authority): "the CA certificate content can't exceed 35 KB"). The API spec bounds `customCATrustCertificates` only by count.
- Each entry is exactly one PEM certificate with LF line endings. Bundles, keys and CRLF are refused at plan.
- Each entry is trimmed and base64-encoded. An empty list maps to `null`, so a cluster without custom CAs plans no change.

**Security:** A CA in the node OS trust store is trusted for every TLS name the node reaches: container registries, public image hosts, and the control plane through the kubelet. Whoever holds its private key can intercept any of that traffic on every node. Use a CA created only for this purpose and name-constrained to what the nodes must trust: X.509 `nameConstraints` with a permitted DNS subtree, or an IP range, that covers only the private registry or endpoint.

Tests: [`tests/ca_trust.tftest.hcl`](tests/ca_trust.tftest.hcl).
