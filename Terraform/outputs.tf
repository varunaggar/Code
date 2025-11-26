output "resource_group_name_Images" {
  value = azurerm_resource_group.rgImages
}

output "resource_group_name_Monitor" {
  value = azurerm_resource_group.rgMonitor
}

output "resource_group_name_Network" {
  value = azurerm_resource_group.rgNetwork
}

output "resource_group_name_Security" {
  value = azurerm_resource_group.rgSec
}

output "resource_group_name_Storage" {
  value = azurerm_resource_group.rgStorage
}

output "resource_group_name_Vault" {
  value = azurerm_resource_group.rgVault
}

output "resource_group_name_loninternet" {
  value       = azurerm_resource_group.Loninternet
  description = "London Internet resource group"
}

output "azurerm_virtual_network_lonVnet" {
  value       = azurerm_virtual_network.loncorpnetcore
  description = "London core virtual network"
}