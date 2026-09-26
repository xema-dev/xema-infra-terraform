variable "name" {
  description = "Name of the VM; prefixes its NIC, public IP and NSG."
  type        = string
}

variable "region" {
  description = "Azure region (must be the VNet's)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the runner in."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the runner lives in (providers/azure/network's management_subnet_id)."
  type        = string
}

variable "vm_size" {
  description = "VM size. The default is a burstable 2 vCPU / 4 GiB — enough for Terraform and the deployment engine, and one of the cheapest sizes that is."
  type        = string
  default     = "Standard_B2als_v2"
}

variable "admin_username" {
  description = "Login name on the VM."
  type        = string
  default     = "runner"
}

variable "ssh_public_keys" {
  description = "SSH public keys allowed to log in. Required and non-empty: password login is disabled. Rotating access at handoff is replacing this list."
  type        = list(string)
}

variable "allowed_ssh_cidrs" {
  description = "Source CIDRs allowed to reach SSH. Required and non-empty; the whole internet is refused. Changing access at handoff is replacing this list."
  type        = list(string)
}

variable "os_disk_size_gb" {
  description = "OS disk size in GiB."
  type        = number
  default     = 64
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}
