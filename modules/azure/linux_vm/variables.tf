variable "location" {
  description = "Azure location (e.g. Norway East)."
  type        = string
}

variable "resource_group_name" {
  description = "Azure resource group name."
  type        = string
}

variable "virtual_network_subnet_id" {
  description = "ID of the virtual network subnet ID to add the VM to."
  type        = string
}

variable "hostname" {
  description = "Prefix to use for resource names (must be unique), as well as for the FQDN."
  type        = string
}

variable "domain" {
  description = "Domain to use for the FQDN."
  type        = string
}

variable "create_reverse_fqdn" {
  description = "To use the FQDN for the PTR record. Must have a matching forward record for validation to succeed. Only IPv4 supported in Azure, currently."
  type        = bool
}

variable "source_image" {
  description = "Source image to use for install (e.g. Debian with details)."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

variable "vm_size" {
  description = "VM size type (e.g. Standard_D2as_v5)."
  type        = string
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB."
  type        = number
}

variable "data_disk_size_gb" {
  description = "Data disk size in GB."
  type        = number
}

variable "data_disk_backup_enable" {
  description = "Create a recovery services vault for the data disk and enable daily backups."
  type        = bool
}

variable "admin_username" {
  description = "Initial VM user (e.g. ansible)."
  type        = string
}

variable "admin_ssh_pubkey" {
  description = "SSH pubkey for initial VM user."
  type        = string
}
