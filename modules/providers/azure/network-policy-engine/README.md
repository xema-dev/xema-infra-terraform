# providers/azure/network-policy-engine

A helper with no provider and no resources, used by [`cluster`](../cluster). It validates the NetworkPolicy engine (`cilium` or `calico`, never none) and maps it to the AKS `network_data_plane` and `network_policy` values.

`cilium` needs AKS-managed Cilium and Linux node pools only. `calico` keeps the Azure data plane.
