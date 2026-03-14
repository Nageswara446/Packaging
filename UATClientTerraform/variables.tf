variable "resource_group_name" {}
variable "vm_name" {}
variable "admin_username" {
  type = string
  default = "install"
}
variable "admin_password" {
  type = string
  sensitive = true
}
variable "subnet_name" {}
variable "vnet" {}
variable "vnet_rg" {}

variable "vm_size" {
  type = string
  default = "Standard_D2as_v5"
}

variable "vm_timezone" {
  type = string
  default = "W. Europe Standard Time"  
}

variable "storage_account_type" {
  type    = string
  default = "StandardSSD_LRS"
}

