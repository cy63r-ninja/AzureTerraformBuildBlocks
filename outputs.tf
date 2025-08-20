output "linux_public_ip" {
  value = azurerm_public_ip.pip_linux.ip_address
}

output "windows_public_ip" {
  value = azurerm_public_ip.pip_windows.ip_address
}

output "law_id" {
  value = azurerm_log_analytics_workspace.law.id
}

# Replace the dce output with this:
output "dce_id" {
  value = azurerm_monitor_data_collection_endpoint.dce.id
}
