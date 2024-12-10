terraform {

  required_version = ">=0.15"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.11.0"
    }
  }
}

provider "azurerm" {
  subscription_id = "d59e013b-b73f-45f3-ba58-1a3a7575a861"
  features {}
}

resource "azurerm_resource_group" "resgrp" {
  name     = "RG4"
  location = "westeurope"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "myVNet"
  resource_group_name = azurerm_resource_group.resgrp.name
  location            = azurerm_resource_group.resgrp.location
  address_space       = ["10.21.0.0/16"]
}

resource "azurerm_subnet" "frontend" {
  name                 = "myAGSubnet"
  resource_group_name  = azurerm_resource_group.resgrp.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.21.0.0/24"]
}

resource "azurerm_subnet" "backend" {
  name                 = "myBackendSubnet"
  resource_group_name  = azurerm_resource_group.resgrp.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.21.1.0/24"]
}

resource "azurerm_public_ip" "pubip" {
  name                = "myAGPublicIPAddress"
  resource_group_name = azurerm_resource_group.resgrp.name
  location            = azurerm_resource_group.resgrp.location
  allocation_method   = "Static"
  sku                 = "Standard"
}


resource "azurerm_application_gateway" "appgtw" {
  name                = "myAppGateway"
  resource_group_name = azurerm_resource_group.resgrp.name
  location            = azurerm_resource_group.resgrp.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = azurerm_subnet.frontend.id
  }

  frontend_port {
    name = var.frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = var.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.pubip.id
  }

  backend_address_pool {
    name = var.backend_address_pool_name
  }

  backend_http_settings {
    name                  = var.http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = var.listener_name
    frontend_ip_configuration_name = var.frontend_ip_configuration_name
    frontend_port_name             = var.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = var.request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = var.listener_name
    backend_address_pool_name  = var.backend_address_pool_name
    backend_http_settings_name = var.http_setting_name
    priority = 10
  }
}

resource "azurerm_network_interface" "nic" {
  for_each = tomap({
    "VM1"= "nic-vm1"
    "VM2"="nic-vm2"
  })
  name = each.value
  location = azurerm_resource_group.resgrp.location
  resource_group_name = azurerm_resource_group.resgrp.location

  ip_configuration {
    name = "${each.key}-ipconfig"
    subnet_id = azurerm_subnet.backend.id
    private_ip_address_allocation = "Dynamic"
  }
}

/*resource "azurerm_network_interface" "nic1" {
  name                = "nic-1"
  location            = azurerm_resource_group.resgrp.location
  resource_group_name = azurerm_resource_group.resgrp.name

  ip_configuration {
    name                          = "nic-ipconfig-1"
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "nic2" {
  name                = "nic-2"
  location            = azurerm_resource_group.resgrp.location
  resource_group_name = azurerm_resource_group.resgrp.name

  ip_configuration {
    name                          = "nic-ipconfig-2"
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Dynamic"
  }
}*/

resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "nic-assoc" {
  for_each = azurerm_network_interface.nic
  network_interface_id = each.value.id
  ip_configuration_name = "${each.key}-ipconfig"
  backend_address_pool_id = one(azurerm_application_gateway.appgtw.backend_address_pool).id
}

/*resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "nic-assc1" {
  network_interface_id    = azurerm_network_interface.nic1.id
  ip_configuration_name   = "nic-ipconfig-1"
  backend_address_pool_id = tolist(azurerm_application_gateway.appgtw.backend_address_pool).0.id
}

resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "nic-assc2" {
  network_interface_id    = azurerm_network_interface.nic2.id
  ip_configuration_name   = "nic-ipconfig-2"
  backend_address_pool_id = tolist(azurerm_application_gateway.appgtw.backend_address_pool).0.id
}*/

resource "random_password" "password" {
  length = 16
  special = true
  lower = true
  upper = true
  numeric = true
}

resource "azurerm_windows_virtual_machine" "VM" {
  for_each = toset(["VM1","VM2"])
  name = each.value
  resource_group_name = azurerm_resource_group.resgrp.name
  location = azurerm_resource_group.resgrp.location
  size="Standard_DS2_v2"
  admin_username = "azureadmin"
  admin_password = random_password.password.result

  network_interface_ids = [
    azurerm_network_interface.nic[each.key].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}

/*resource "azurerm_windows_virtual_machine" "vm1" {
  name                = "VM1"
  resource_group_name = azurerm_resource_group.resgrp.name
  location            = azurerm_resource_group.resgrp.location
  size                = "Standard_DS2_v2"
  admin_username      = "azureadmin"
  admin_password      = random_password.password.result

  network_interface_ids = [
    azurerm_network_interface.nic1.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }


  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}

resource "azurerm_windows_virtual_machine" "vm2" {
  name                = "VM2"
  resource_group_name = azurerm_resource_group.resgrp.name
  location            = azurerm_resource_group.resgrp.location
  size                = "Standard_DS2_v2"
  admin_username      = "azureadmin"
  admin_password      = random_password.password.result

  network_interface_ids = [
    azurerm_network_interface.nic2.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }


  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}*/

resource "azurerm_virtual_machine_extension" "vm-extensions" {
  for_each = toset(["VM1","VM2"])
  name = "${each.value}-ext"
  virtual_machine_id = azurerm_windows_virtual_machine.VM[each.key].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
    {
        "commandToExecute": "powershell Add-WindowsFeature Web-Server; powershell Add-Content -Path \"C:\\inetpub\\wwwroot\\Default.htm\" -Value $($env:computername)"
    }
SETTINGS
}

/*resource "azurerm_virtual_machine_extension" "vm-extensions1" {
  name                 = "vm1-ext"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm1.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
    {
        "commandToExecute": "powershell Add-WindowsFeature Web-Server; powershell Add-Content -Path \"C:\\inetpub\\wwwroot\\Default.htm\" -Value $($env:computername)"
    }
SETTINGS
}

resource "azurerm_virtual_machine_extension" "vm-extensions2" {
  name                 = "vm2-ext"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm2.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
    {
        "commandToExecute": "powershell Add-WindowsFeature Web-Server; powershell Add-Content -Path \"C:\\inetpub\\wwwroot\\Default.htm\" -Value $($env:computername)"
    }
SETTINGS
}*/

output "appgw_public_ip_address" {
  description = "The public IP address of Application Gateway."
  value       = azurerm_public_ip.pubip.ip_address
}


