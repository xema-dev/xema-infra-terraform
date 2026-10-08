# `providers/azure/network-policy-engine`

Pure helper (no provider, no resources) used by [`cluster`](../cluster/README.md): validates the
NetworkPolicy engine (`cilium` default | `azure` | `calico`; never "none") and maps it to the AKS
`network_data_plane` / `network_policy` values.
