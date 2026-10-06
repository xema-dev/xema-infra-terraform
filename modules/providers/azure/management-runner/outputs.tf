output "public_ip_address" {
  description = "The runner's public IP: the SSH target, and its egress address — add it to the cluster's authorized_ip_ranges so the runner can reach the Kubernetes API. null when public_ip_enabled = false."
  value       = one(azurerm_public_ip.this[*].ip_address)
}

output "private_ip_address" {
  description = "The runner's address inside the VNet."
  value       = azurerm_network_interface.this.private_ip_address
}

output "principal_id" {
  description = "Object id of the runner's managed identity, for the role assignments the deployment grants it."
  value       = azurerm_linux_virtual_machine.this.identity[0].principal_id
}

output "admin_username" {
  description = "Login name on the VM."
  value       = var.admin_username
}

output "network_security_group_id" {
  description = "Id of the runner's NIC network security group, so consumers can attach further inbound rules (priorities 120-4095; 100, 110 and 4096 are taken)."
  value       = azurerm_network_security_group.this.id
}

output "network_security_group_name" {
  description = "Name of the runner's NIC network security group."
  value       = azurerm_network_security_group.this.name
}
