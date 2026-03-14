data "azurerm_resource_group" "resourcegroup01" {
    name = var.resource_group_name
}

data "azurerm_virtual_network" "azvnet" {
    name = "${var.vnet}"
    resource_group_name = var.vnet_rg
}

data "azurerm_subnet" "subnet" {
    name                 = "${var.subnet_name}"
    resource_group_name  = var.vnet_rg
    virtual_network_name = "${data.azurerm_virtual_network.azvnet.name}"
}


resource "azurerm_network_interface" "vm_nic" {
  name                = join("", ["${var.vm_name}", "${random_id.random.dec}"])
  location            = "${data.azurerm_resource_group.resourcegroup01.location}"
  resource_group_name = "${data.azurerm_resource_group.resourcegroup01.name}"
  accelerated_networking_enabled = true
  ip_configuration {
    name                          = "primary"
    subnet_id                     = "${data.azurerm_subnet.subnet.id}"
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = "${data.azurerm_resource_group.resourcegroup01.name}"
  location            = "${data.azurerm_resource_group.resourcegroup01.location}"
  size                = var.vm_size
  enable_automatic_updates = "false"
  patch_mode               = "Manual"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  timezone            = var.vm_timezone
  secure_boot_enabled = true
  vtpm_enabled = true
  custom_data = "${filebase64("${path.module}/files/winrm.ps1")}"

  network_interface_ids = [
    azurerm_network_interface.vm_nic.id,
  ]
  os_disk {
    name                 = join("_", [var.vm_name, "OsDisk"])
    caching              = "ReadWrite"
    storage_account_type = var.storage_account_type
    disk_size_gb         = 127
  }


  additional_unattend_content {
    content = local.auto_logon_data
    setting = "AutoLogon"
  }

  additional_unattend_content {
    content = local.first_logon_data
    setting = "FirstLogonCommands"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-ent-cpc"
    sku       = "win11-24h2-ent-cpc"
    version   = "latest"
  }
}


resource "azurerm_virtual_machine_extension" "run-ps" {
  name                 = "run-ps"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"
  settings = <<SETTINGS
  {
    "commandToExecute": "powershell.exe -Command \"${local.powershell_command}\""
  }
SETTINGS
}

