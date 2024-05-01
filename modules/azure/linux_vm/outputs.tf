output "vm" {
  description = "List of managed VMs and associated details."
  value = {
    ipv4_address = azurerm_public_ip.main_ipv4.ip_address
    ipv6_address = azurerm_public_ip.main_ipv6.ip_address
  }
}
