# `stacks/azure/xema-foundation`

What must exist before `stacks/azure/xema-substrate` runs: the resource group,
the network (`providers/azure/network`) with its private DNS zones, and the
management runner (`providers/azure/management-runner`).

| step | what | run from |
| --- | --- | --- |
| 0 | `modules/providers/azure/state-bucket` | anywhere, once |
| 1 | **this stack** | anywhere — it touches only the Azure control plane |
| 2 | `stacks/azure/xema-substrate` | the management runner |

Pass the `network` output to the substrate's `network` input unchanged, and add
`management_runner.public_ip_address` to the substrate's
`cluster_authorized_ip_ranges`.

Everything here belongs to the deployment and survives a handoff untouched:
handing over is replacing the runner's SSH keys and allowlist and the
identities granted roles, never moving a resource.
