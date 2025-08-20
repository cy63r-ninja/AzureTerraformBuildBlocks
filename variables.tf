variable "prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "demo"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "uksouth"
}

variable "admin_username" {
  description = "Admin username for both VMs"
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "Admin password for Windows VM (also optional fallback for Linux)"
  type        = string
  sensitive   = true
}

variable "linux_ssh_public_key" {
  description = "SSH public key for the Linux VM (recommended)"
  type        = string
  default     = "" # paste your ssh-rsa... here, or leave blank to allow password auth
}
