#Resource_Groups

resource "azurerm_resource_group" "rgNetwork" {
  provider = azurerm.Main
  name     = "${var.prefix}-Network"
  location = var.Location
}

resource "azurerm_resource_group" "rgStorage" {
  provider = azurerm.Main
  name     = "${var.prefix}-Storage"
  location = var.Location
}

resource "azurerm_resource_group" "rgMonitor" {
  provider = azurerm.Main
  name     = "${var.prefix}-Monitoring"
  location = var.Location
}

resource "azurerm_resource_group" "rgVault" {
  provider = azurerm.Main
  name     = "${var.prefix}-Vault"
  location = var.Location
}

resource "azurerm_resource_group" "rgSec" {
  provider = azurerm.Main
  name     = "${var.prefix}-Security"
  location = var.Location
}

resource "azurerm_resource_group" "rgImages" {
  provider = azurerm.Main
  name     = "${var.prefix}-Images"
  location = var.Location
}

resource "azurerm_resource_group" "Loninternet" {
  provider = azurerm.Main
  name     = "${var.prefix}-Internet"
  location = var.Location
  tags = {
    environment = "PROD"
    Office      = "London"
    type        = "External"

  }
}

resource "azurerm_resource_group" "lonDC" {
  provider = azurerm.Main
  name     = "${var.prefix}-DC01"
  location = var.Location
}

#terraform state list
#terraform state show resource path
#terraform show
#terraform plan
#terraform plan -out tfplan
#terraform validate
#terraform fmt

