
resource "azurerm_network_security_group" "loncorpnetNSGInfra" {
  provider            = azurerm.Main
  name                = "${var.prefix}-Core-Network-NSGInfra"
  location            = var.Location
  resource_group_name = azurerm_resource_group.rgNetwork.name
}

resource "azurerm_network_security_group" "loncorpnetNSGClients" {
  provider            = azurerm.Main
  name                = "${var.prefix}-Core-Network-NSGClients"
  location            = var.Location
  resource_group_name = azurerm_resource_group.rgNetwork.name

}

/*
resource "azurerm_network_ddos_protection_plan" "loncorpnetddos" {
  provider = azurerm.Main
  name                = "${var.prefix}-ddospplan1"
  location            = var.Location
  resource_group_name = azurerm_resource_group.rgNetwork.name
}
*/

resource "azurerm_virtual_network" "loncorpnetcore" {
  provider            = azurerm.Main
  name                = "Corp-Lon-Core-VNET"
  location            = "uksouth"
  resource_group_name = "Corp-Lon-Network"
  address_space       = ["10.0.0.0/16"]
  dns_servers         = ["10.0.0.4", "10.0.0.5"]

  //ddos_protection_plan {
  //  id     = azurerm_network_ddos_protection_plan.loncorpnetddos.name
  //  enable = false
  //}

  subnet {
    name           = "${var.prefix}-Core-VNET-Subnet-Infra"
    address_prefix = "10.0.1.0/24"
    security_group = azurerm_network_security_group.loncorpnetNSGInfra.id
  }

}

resource "azurerm_subnet" "subnetInfra" {
  provider             = azurerm.Main
  name                 = "${var.prefix}-Core-VNET-Subnet-Clients"
  resource_group_name  = azurerm_resource_group.rgNetwork.name
  virtual_network_name = azurerm_virtual_network.loncorpnetcore.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_security_group" "Lonintenretnsg" {
  provider            = azurerm.Main
  name                = "${var.prefix}-Internet-NSG"
  location            = azurerm_resource_group.Loninternet.location
  resource_group_name = azurerm_resource_group.Loninternet.name
  tags = {

    environment = "PROD"
    Office      = "London"
    type        = "External"

  }
}

resource "azurerm_virtual_network" "loninternetvnet" {
  provider            = azurerm.Main
  name                = "${var.prefix}-Internet-Vnet"
  location            = azurerm_resource_group.Loninternet.location
  resource_group_name = azurerm_resource_group.Loninternet.name
  address_space       = ["20.0.0.0/16"]
  //dns_servers         = ["20.0.0.4", "20.0.0.5"]

  subnet {
    name           = "${var.prefix}-Internet-Subnet"
    address_prefix = "20.0.1.0/24"
    security_group = azurerm_network_security_group.Lonintenretnsg.id
  }
  tags = {
    environment = "Production"
    Office      = "London"
    type        = "External"
  }
}