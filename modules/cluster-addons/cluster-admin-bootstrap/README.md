# cluster-admin-bootstrap

Applies the engine-generated cluster-admin chart (CRDs kept on uninstall, cluster-scope RBAC,
the ValidatingWebhookConfiguration) with Helm, from a root that holds cluster-admin rights.

- `apply_via = "in-vnet"`: `helm_release` (helm provider >= 3.1, `take_ownership`).
- `apply_via = "run-command"`: `helm upgrade --install ... --take-ownership` through AKS
  run-command (private cluster). The zip holds only `chart_path`; no registry credential or
  secret is in the request. A non-zero exit code fails the apply and quotes the logs.

There is no fallback between the modes. `release_namespace` must not be writable by the
deployer: a forged release Secret would make Helm delete with cluster-admin rights.

## run-command credentials and operation

- `cluster_token` (ephemeral, sensitive) is required with `run-command`. AKS with Entra and
  local accounts disabled gives the run-command pod no credential otherwise. Set it from the
  environment, never a tfvars file:
  `export TF_VAR_cluster_token=$(az account get-access-token --resource 6dae42f8-4368-4678-94ff-3960e28e3630 --query accessToken -o tsv)`.
  It is sent through azapi's write-only `sensitive_body`, so it is in neither plan nor state.
  Needs OpenTofu/Terraform >= 1.11 and azapi >= 2.11.
- The zip is made with `exclude_symlink_directories`; still check that the chart directory has
  no symlinks. `chart_archive_path` must not be inside `chart_path`.
- A failed run stays in state; rerun with `tofu apply -replace=<address>`
  (`module.<name>.azapi_resource_action.run_command[0]`).
