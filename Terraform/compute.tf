/*resource "azurerm_resource_group" "example" {
  name     = "example-resources"
  location = "West US"
}

resource "azurerm_image" "example" {
  name                = "acctest"
  location            = "West US"
  resource_group_name = azurerm_resource_group.example.name

  os_disk {
    os_type  = "Linux"
    os_state = "Generalized"
    blob_uri = "{blob_uri}"
    size_gb  = 30
  }
}
  resource "azurerm_network_interface" "nicDC01" {
  name                = "${var.prefix}-Nic-DC01"
  location            = azurerm_resource_group.lonDC.location
  resource_group_name = azurerm_resource_group.lonDC.name

  ip_configuration {
    name                          = "${var.prefix}-IP-DC01"
    subnet_id                     = azurerm_virtual_network
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "example" {
  name                = "example-machine"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  admin_password      = "P@$w0rd1234!"
  network_interface_ids = [
    azurerm_network_interface.example.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
}

*/