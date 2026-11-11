# customer-cluster-admin

Applies the committed cluster-admin chart (`bootstrap/cluster-admin/`) with cluster-admin
rights. CI never holds those rights; the customer's admin runs this root.

- Run it from the admin's laptop (`az login`, then `terraform init && terraform apply`).
  It has its own backend block (separate key) and its own state and identity.
- `apply_via = "run-command"` reaches a private AKS cluster through AKS run-command; it
  never falls back to the helm provider. Use `in-vnet` only where the API server is reachable.
- Regenerate the chart, then commit it:
  `xema-deployment-engine plan --root <dir> --scope infra --regenerate-cluster-admin-chart`
- Helm adopts the objects that were hand-applied earlier (`--take-ownership`). After that
  first apply nobody hand-applies these objects again.
- Edit `chart_path` in `main.tf` if the root repo keeps the chart elsewhere.
- `release_namespace` must stay a namespace the deployer cannot write.
- With `run-command`, export the admin's token first (environment only, never a tfvars file,
  never committed):
  `export TF_VAR_cluster_token=$(az account get-access-token --resource 6dae42f8-4368-4678-94ff-3960e28e3630 --query accessToken -o tsv)`.
- State holds the run output and cluster details: keep it in a storage account/container the
  deployer/CI identity cannot read or write.
- A failed run stays in state; rerun with `tofu apply -replace=module.cluster_admin.azapi_resource_action.run_command[0]`.
- Check the chart directory has no symlinks.
