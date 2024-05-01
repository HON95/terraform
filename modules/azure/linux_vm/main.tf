locals {
  fqdn = "${var.hostname}.${var.domain}"
}

resource "azurerm_public_ip" "main_ipv4" {
  name                = "${var.hostname}_ipv4"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  sku_tier            = "Regional"
  domain_name_label   = replace(local.fqdn, "/[^a-z0-9-]/", "-")
  reverse_fqdn        = var.create_reverse_fqdn ? local.fqdn : null
  ip_version          = "IPv4"
  lifecycle {
    create_before_destroy = true
  }
}
resource "azurerm_public_ip" "main_ipv6" {
  name                = "${var.hostname}_ipv6"
  location            = azurerm_public_ip.main_ipv4.location
  resource_group_name = azurerm_public_ip.main_ipv4.resource_group_name
  allocation_method   = azurerm_public_ip.main_ipv4.allocation_method
  sku                 = azurerm_public_ip.main_ipv4.sku
  sku_tier            = azurerm_public_ip.main_ipv4.sku_tier
  domain_name_label   = azurerm_public_ip.main_ipv4.domain_name_label
  reverse_fqdn        = null # Not supported for IPv6 yet
  ip_version          = "IPv6"
  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_network_security_group" "main" {
  name                = "${var.hostname}_nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  # ICMP
  security_rule {
    priority                   = 100
    name                       = "ICMP"
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # SSH
  security_rule {
    priority                   = 110
    name                       = "SSH"
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # HTTP(S)
  security_rule {
    priority                   = 120
    name                       = "HTTP"
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "main" {
  name                = "${var.hostname}_nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "ipconfig4"
    primary                       = true
    subnet_id                     = var.virtual_network_subnet_id
    private_ip_address_version    = "IPv4"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main_ipv4.id
  }
  ip_configuration {
    name                          = "ipconfig6"
    primary                       = false
    subnet_id                     = var.virtual_network_subnet_id
    private_ip_address_version    = "IPv6"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main_ipv6.id
  }
}

resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "random_id" "diag_name" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = var.resource_group_name
  }
  byte_length = 4
}

resource "azurerm_storage_account" "main" {
  # Name can't contain underscore or hyphen ...
  name                     = "diag${random_id.diag_name.hex}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_linux_virtual_machine" "main" {
  name                  = "${var.hostname}_vm"
  location              = var.location
  resource_group_name   = var.resource_group_name
  network_interface_ids = [azurerm_network_interface.main.id]
  size                  = var.vm_size
  computer_name         = var.hostname
  admin_username        = var.admin_username

  os_disk {
    name                 = "${var.hostname}_os_disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.source_image.publisher
    offer     = var.source_image.offer
    sku       = var.source_image.sku
    version   = var.source_image.version
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_pubkey
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.main.primary_blob_endpoint
  }
}

resource "azurerm_managed_disk" "main" {
  name                 = "${var.hostname}_data_disk"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
}

resource "azurerm_virtual_machine_data_disk_attachment" "main" {
  managed_disk_id    = azurerm_managed_disk.main.id
  virtual_machine_id = azurerm_linux_virtual_machine.main.id
  lun                = "10"
  caching            = "ReadWrite"
}

resource "random_id" "rsv_name" {
  count = var.data_disk_backup_enable ? 1 : 0
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = var.resource_group_name
  }
  byte_length = 4
}

resource "azurerm_recovery_services_vault" "main" {
  count = var.data_disk_backup_enable ? 1 : 0
  # Name can't contain underscore ...
  name                = "rsv${random_id.rsv_name[0].hex}-${var.hostname}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
}

resource "azurerm_backup_policy_vm" "main" {
  count               = var.data_disk_backup_enable ? 1 : 0
  name                = "${var.hostname}_backup_pol"
  resource_group_name = var.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.main[0].name

  backup {
    frequency = "Daily"
    time      = "05:00"
  }

  retention_daily {
    count = 10
  }
}

resource "azurerm_backup_protected_vm" "main" {
  count               = var.data_disk_backup_enable ? 1 : 0
  resource_group_name = var.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.main[0].name
  backup_policy_id    = azurerm_backup_policy_vm.main[0].id
  source_vm_id        = azurerm_linux_virtual_machine.main.id
}
