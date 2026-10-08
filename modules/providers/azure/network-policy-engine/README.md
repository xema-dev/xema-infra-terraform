# `providers/azure/network-policy-engine`

Pure helper (no provider, no resources) used by [`cluster`](../cluster/README.md): validates the
NetworkPolicy engine (`cilium` default | `calico`; never "none") and maps it to the AKS
`network_data_plane` / `network_policy` values.

The `cilium` engine requires AKS-managed Cilium (Azure CNI Powered by Cilium) and **Linux node
pools only**. `calico` keeps the Azure dataplane. Azure Network Policy Manager is not offered (on a
retirement path; overlay support unverified).
