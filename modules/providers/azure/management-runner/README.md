# `providers/azure/management-runner`

One small Linux VM inside the deployment's network: the deployment's
**management runner**. There is no VPN.

- **Why it exists.** With PostgreSQL, the cache, the storage account and the key
  vault reachable only through the VNet, anything that writes INSIDE them —
  PostgreSQL roles and grants, Key Vault secrets, the deployment engine — has to
  run from inside the network. This is that place, and it is also restricted SSH
  access for a human.
- **Access.** SSH public keys only (password login disabled). Inbound SSH only
  from `allowed_ssh_cidrs`, which is required and may not be the whole internet.
  The NSG always carries an explicit inbound DenyAll (priority 4096) above
  Azure's default AllowVnetInBound, so the VNet and any routed customer network
  cannot reach the VM on any other port; only `AzureLoadBalancer` (110) and the
  SSH allowlist (100) are allowed. There is no input to loosen this; add rules
  through the `network_security_group_id` output (priorities 120-4095). Run
  command needs no inbound.
- **Identity.** A system-assigned managed identity, so Terraform and the engine
  need no stored credential. What it may do is granted by the deployment
  (`principal_id` output), never by this module.
- **Base only.** cloud-init installs packages from signed distribution
  repositories (git, jq, the PostgreSQL and Redis clients, the Azure CLI). The
  deployment TOOLING is not installed here: it is pinned by the deployment's own
  lock and installed from artifacts the customer controls, so rebuilding the VM
  can never silently change a tool version.
- **Ownership.** It belongs to the deployment. At handoff it stays where it is;
  only `ssh_public_keys`, `allowed_ssh_cidrs` and the identity's grants change.

The default size, `Standard_B2als_v2` (2 vCPU / 4 GiB, burstable), is one of the
cheapest sizes that runs Terraform and the engine comfortably.

**Zone pinning.** `zone` ("1", "2" or "3") is optional; empty lets Azure choose,
which is the unchanged behaviour. Pin it when the subscription marks a zone
`NotAvailableForSubscription` for the VM family: the placement then fails or
lands somewhere unwanted. The resource SKUs API shows it
(`az vm list-skus --location <region> --size <vm_size> --zone` and read the
`restrictions`).

Outputs: `public_ip_address` (the SSH target and the runner's egress address —
add it to the cluster's `authorized_ip_ranges`), `private_ip_address`,
`principal_id`, `admin_username`, `network_security_group_id`,
`network_security_group_name`.
