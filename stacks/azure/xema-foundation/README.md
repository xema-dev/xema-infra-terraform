# stacks/azure/xema-foundation

What must exist before [`stacks/azure/xema-substrate`](../xema-substrate) runs: the resource group, the network ([`providers/azure/network`](../../../modules/providers/azure/network)) with its private DNS zones, and the management runner ([`providers/azure/management-runner`](../../../modules/providers/azure/management-runner)).

## Usage

| Step | What | Run from |
| --- | --- | --- |
| 0 | [`providers/azure/state-bucket`](../../../modules/providers/azure/state-bucket), once | anywhere |
| 1 | this stack, which touches only the Azure control plane | anywhere |
| 2 | `stacks/azure/xema-substrate` | the management runner |

Pass this stack's `network` output unchanged to the substrate's `network` input, and add `management_runner.public_ip_address` to the substrate's `cluster_authorized_ip_ranges`.
