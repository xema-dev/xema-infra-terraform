# providers/azure/cluster-upgrades

A helper with no provider and no resources, used by [`cluster`](../cluster). It validates the AKS version, upgrade channels and maintenance windows and passes them to `azurerm_kubernetes_cluster`. It is separate so its rules run under `terraform test` with no provider, on Terraform 1.6 and OpenTofu.

- `kubernetes_version` is a minor alias (`"1.34"`) or a full version (`"1.34.12"`).
- `automatic_upgrade_channel` and `node_os_upgrade_channel` pass through; null leaves them to Azure.
- A maintenance window needs `frequency`, `interval` and a `duration` of 4 to 24 hours, plus `day_of_week` (Weekly, RelativeMonthly), `day_of_month` (AbsoluteMonthly) or `week_index` (RelativeMonthly) as the frequency requires. It comes out as a list of zero or one for a `dynamic` block.

Tests: [`tests/cluster_upgrades.tftest.hcl`](tests/cluster_upgrades.tftest.hcl).
