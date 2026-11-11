# cluster-admin-bootstrap

Applies the engine-generated cluster-admin chart (CRDs kept on uninstall, cluster-scope RBAC,
the ValidatingWebhookConfiguration) with Helm, from a root that holds cluster-admin rights.

- `apply_via = "in-vnet"`: `helm_release` (helm provider >= 3.1, `take_ownership`).
- `apply_via = "run-command"`: `helm upgrade --install ... --take-ownership` through AKS
  run-command (private cluster). The zip holds only `chart_path`; no registry credential or
  secret is in the request. A non-zero exit code fails the apply and quotes the logs.

There is no fallback between the modes. `release_namespace` must not be writable by the
deployer: a forged release Secret would make Helm delete with cluster-admin rights.
