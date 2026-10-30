# ---------------------------------------------------------------------------
# The deployment's MANAGEMENT RUNNER: one small VM inside the VNet.
#
# It is the one place from which the private data planes are reachable — the
# PostgreSQL server (roles and grants are created inside it), the Key Vault,
# the cache and the storage account — so Terraform's data-plane resources and
# the deployment engine run HERE. It is also restricted SSH access for a human.
# There is no VPN.
#
# It belongs to the DEPLOYMENT, not to whoever operates it: at handoff it stays
# exactly where it is and only the SSH keys and the allowlist change.
# ---------------------------------------------------------------------------

locals {
  # Refused as an SSH source: each means "the whole internet".
  open_sources = ["0.0.0.0/0", "::/0", "*", "Internet", "Any"]
}

resource "azurerm_public_ip" "this" {
  count = var.public_ip_enabled ? 1 : 0

  name                = "${var.name}-pip"
  location            = var.region
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_security_group" "this" {
  name                = "${var.name}-nsg"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Safe default, never opt-in: inbound is SSH from the declared sources and
  # the Azure load balancer probe, then an explicit DenyAll. Azure's default
  # AllowVnetInBound (65000) would otherwise let the whole routed network reach
  # the VM on any port. Priorities: ssh 100, load balancer 110, deny 4096 (the
  # highest a custom rule may take). Further rules attached through the
  # network_security_group_id output use 120-4095.
  dynamic "security_rule" {
    for_each = length(var.allowed_ssh_cidrs) > 0 ? [1] : []
    content {
      name                       = "ssh-from-allowlist"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefixes    = var.allowed_ssh_cidrs
      destination_address_prefix = "*"
    }
  }

  security_rule {
    name                       = "allow-azure-load-balancer"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "this" {
  name                = "${var.name}-nic"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = one(azurerm_public_ip.this[*].id)
  }
}

resource "azurerm_network_interface_security_group_association" "this" {
  network_interface_id      = azurerm_network_interface.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

# With no extra_cloud_init the VM gets the module's file alone, byte for byte as
# before (a custom_data change can replace the VM). With one, the two documents
# are merged by cloud-init at first boot.
data "cloudinit_config" "this" {
  count = var.extra_cloud_init != "" ? 1 : 0

  gzip          = false
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content      = file("${path.module}/cloud-init.yaml")
  }

  part {
    content_type = "text/cloud-config"
    content      = var.extra_cloud_init
    merge_type   = "list(append)+dict(no_replace,recurse_list)+str()"
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  name                  = var.name
  location              = var.region
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  zone                  = var.zone != "" ? var.zone : null
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.this.id]
  tags                  = var.tags

  disable_password_authentication = true
  custom_data                     = var.extra_cloud_init != "" ? data.cloudinit_config.this[0].rendered : base64encode(file("${path.module}/cloud-init.yaml"))

  dynamic "admin_ssh_key" {
    for_each = toset(var.ssh_public_keys)
    content {
      username   = var.admin_username
      public_key = admin_ssh_key.value
    }
  }

  # A managed identity so Terraform and the engine can run here without a
  # stored credential. What it may do is granted by the deployment, never here.
  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  lifecycle {
    precondition {
      condition     = (!var.public_ip_enabled || length(var.allowed_ssh_cidrs) > 0) && length(setintersection(var.allowed_ssh_cidrs, local.open_sources)) == 0
      error_message = "With a public IP, allowed_ssh_cidrs must name at least one source; and no entry may be the whole internet (0.0.0.0/0, ::/0, *, Internet, Any)."
    }
    precondition {
      condition     = length(var.ssh_public_keys) > 0
      error_message = "ssh_public_keys must hold at least one key: password login is disabled."
    }
  }
}

# The public IP became optional (count); an existing single instance keeps its
# identity instead of being destroyed and recreated.
moved {
  from = azurerm_public_ip.this
  to   = azurerm_public_ip.this[0]
}
