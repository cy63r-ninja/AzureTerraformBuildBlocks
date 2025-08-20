# ----------------------------------------
# Resource Group
# ----------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
}

# ----------------------------------------
# Networking
# ----------------------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.10.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH-22"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-RDP-3389"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# ----------------------------------------
# Public IPs + NICs
# ----------------------------------------
resource "azurerm_public_ip" "pip_linux" {
  name                = "${var.prefix}-linux-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "pip_windows" {
  name                = "${var.prefix}-windows-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic_linux" {
  name                = "${var.prefix}-linux-nic"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip_linux.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_linux_nsg" {
  network_interface_id      = azurerm_network_interface.nic_linux.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_network_interface" "nic_windows" {
  name                = "${var.prefix}-windows-nic"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip_windows.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_windows_nsg" {
  network_interface_id      = azurerm_network_interface.nic_windows.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ----------------------------------------
# Log Analytics Workspace
# ----------------------------------------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "LAW-test"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# ----------------------------------------
# Data Collection Endpoint (DCE)
# ----------------------------------------
resource "azurerm_monitor_data_collection_endpoint" "dce" {
  name                = "${var.prefix}-dce"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # public network access is OK for this basic example
  public_network_access_enabled = true
}

# ----------------------------------------
# Linux VM (Ubuntu 24.04 LTS)
# ----------------------------------------
resource "random_string" "linux_vmname_suffix" {
  length  = 4
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "azurerm_linux_virtual_machine" "linux" {
  name                = "${var.prefix}-linux-${random_string.linux_vmname_suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2ms"
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.nic_linux.id
  ]

  # Ubuntu 24.04 LTS ("Noble")
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-noble"
    sku       = "24_04-lts"
    version   = "latest"
  }

  os_disk {
    name                 = "${var.prefix}-linux-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  disable_password_authentication = length(trim(var.linux_ssh_public_key)) > 0

  dynamic "admin_ssh_key" {
    for_each = length(trim(var.linux_ssh_public_key)) > 0 ? [1] : []
    content {
      username   = var.admin_username
      public_key = var.linux_ssh_public_key
    }
  }

  # Optional fallback if no SSH key is provided
  dynamic "admin_password" {
    for_each = length(trim(var.linux_ssh_public_key)) == 0 ? [1] : []
    content {
      # not a real block type; Linux VM resource uses admin_password directly
    }
  }

  # if no SSH key, set admin_password directly
  provisioner "local-exec" {
    when    = create
    command = "echo '' > /dev/null"
  }

  # Set admin_password attribute only when needed (workaround using lifecycle + nulls)
  admin_password = length(trim(var.linux_ssh_public_key)) == 0 ? var.admin_password : null
}

# AMA extension (Linux)
resource "azurerm_virtual_machine_extension" "ama_linux" {
  name                 = "AzureMonitorLinuxAgent"
  virtual_machine_id   = azurerm_linux_virtual_machine.linux.id
  publisher            = "Microsoft.Azure.Monitor"
  type                 = "AzureMonitorLinuxAgent"
  type_handler_version = "1.0"
  automatic_upgrade_enabled = true
}

# ----------------------------------------
# Windows VM (Server)
# ----------------------------------------
resource "random_string" "windows_vmname_suffix" {
  length  = 4
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "azurerm_windows_virtual_machine" "windows" {
  name                = "${var.prefix}-win-${random_string.windows_vmname_suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2ms"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.nic_windows.id
  ]

  # Windows Server (Datacenter) image (closest to "Windows Server Std")
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }

  os_disk {
    name                 = "${var.prefix}-windows-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  enable_automatic_updates = true
  patch_mode               = "AutomaticByOS"
}

# AMA extension (Windows)
resource "azurerm_virtual_machine_extension" "ama_windows" {
  name                 = "AzureMonitorWindowsAgent"
  virtual_machine_id   = azurerm_windows_virtual_machine.windows.id
  publisher            = "Microsoft.Azure.Monitor"
  type                 = "AzureMonitorWindowsAgent"
  type_handler_version = "1.0"
  automatic_upgrade_enabled = true
}

# ----------------------------------------
# DCR: Linux (Syslog: auth, authpriv, syslog)
# ----------------------------------------
resource "azurerm_monitor_data_collection_rule" "dcr_linux" {
  name                        = "${var.prefix}-dcr-linux"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = azurerm_resource_group.rg.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  destinations {
    log_analytics {
      name                  = "law-dest"
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["law-dest"]
  }

  data_sources {
    syslog {
      name           = "linux-syslog"
      facility_names = ["auth", "authpriv", "syslog"]
      log_levels     = ["Debug", "Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
    }
  }
}

# Associate Linux DCR to the Linux VM
resource "azurerm_monitor_data_collection_rule_association" "assoc_linux" {
  name                    = "${var.prefix}-assoc-linux"
  target_resource_id      = azurerm_linux_virtual_machine.linux.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.dcr_linux.id
  description             = "Associate Linux DCR to Linux VM"
}

# ----------------------------------------
# DCR: Windows (Application, Security, System)
# ----------------------------------------
resource "azurerm_monitor_data_collection_rule" "dcr_windows" {
  name                        = "${var.prefix}-dcr-windows"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = azurerm_resource_group.rg.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  destinations {
    log_analytics {
      name                  = "law-dest"
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
    }
  }

  data_flow {
    streams      = ["Microsoft-WindowsEvent"]
    destinations = ["law-dest"]
  }

  data_sources {
    windows_event_log {
      name           = "win-events"
      streams        = ["Microsoft-WindowsEvent"]
      # Collect core channels (Application, Security, System)
      xPath_queries = [
        "Application!*[System[(Level >= 0)]]",
        "Security!*[System[(Level >= 0)]]",
        "System!*[System[(Level >= 0)]]"
      ]
    }
  }
}

# Associate Windows DCR to the Windows VM
resource "azurerm_monitor_data_collection_rule_association" "assoc_windows" {
  name                    = "${var.prefix}-assoc-windows"
  target_resource_id      = azurerm_windows_virtual_machine.windows.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.dcr_windows.id
  description             = "Associate Windows DCR to Windows VM"
}
