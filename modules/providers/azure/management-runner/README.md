# providers/azure/management-runner

One small Linux VM inside the deployment's network, used to reach resources that are only reachable through the VNet.

## When to use it

Use it when PostgreSQL, the cache, storage and the key vault are private and something must write inside them (roles and grants, Key Vault secrets, the deployment engine), or when a human needs restricted SSH access.

## Usage

```hcl
module "runner" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/management-runner?ref=v0.13.0"

  name              = "acme-dev-runner"
  region            = "westeurope"
  resource_group_name = module.network.resource_group_name
  subnet_id         = module.network.management_subnet_id
  ssh_public_keys   = [var.ssh_public_key]
  allowed_ssh_cidrs = ["203.0.113.0/24"]
}
```

- SSH uses public keys only, and only from `allowed_ssh_cidrs`, which must be set and may not be the whole internet. The network security group denies all other inbound traffic; add rules through the `network_security_group_id` output (priorities 120-4095).
- The VM has a system-assigned identity. Grant its permissions to `principal_id` yourself.
- cloud-init installs only base packages; deployment tooling is not installed here.
- `zone` is optional; pin it when your subscription restricts a zone for the VM size.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Name of the VM; prefixes its NIC, public IP and NSG. |
| `region` | yes | Azure region (must be the VNet's). |
| `resource_group_name` | yes | Resource group to create the runner in. |
| `subnet_id` | yes | Subnet the runner lives in (providers/azure/network's management_subnet_id). |
| `vm_size` | no | VM size. |
| `zone` | no | Availability zone for the VM ("1", "2", "3"). |
| `admin_username` | no | Login name on the VM. |
| `ssh_public_keys` | yes | SSH public keys allowed to log in. |
| `allowed_ssh_cidrs` | no | Source CIDRs allowed to reach SSH. |
| `public_ip_enabled` | no | Give the VM a public IP (default true). |
| `extra_cloud_init` | no | An extra cloud-config document merged with the module's own at first boot (default empty: the module's alone). Lists such as `bootcmd`, `write_files` and `packages` are appended; keys the module already sets are kept. Changing it changes `custom_data` and replaces the VM. |
| `os_disk_size_gb` | no | OS disk size in GiB. |
| `tags` | no | Tags applied to every taggable resource. |

Outputs: `public_ip_address`, `private_ip_address`, `principal_id`, `admin_username`, `network_security_group_id`, `network_security_group_name`, `vm_id`.
