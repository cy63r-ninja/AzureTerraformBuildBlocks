output "linux_public_ip" {
  value = azurerm_public_ip.pip_linux.ip_address
}

output "windows_public_ip" {
  value = azurerm_public_ip.pip_windows.ip_address
}

output "law_id" {
  value = azurerm_log_analytics_workspace.law.id
}

output "dce_uri" {
  value = azurerm_monitor_data_collection_endpoint.dce.public_network_access_enabled ? azurerm_monitor_data_collection_endpoint.dce.endpoint : "private-only"
}
