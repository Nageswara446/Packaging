variable "resource_group_name" {}
variable "vm_name" {}
variable "admin_username" {
  type = string
  default = "PackagerAdmin"
}
variable "admin_password" {
  type = string
  sensitive = true
}
variable "subnet_name" {}
variable "vnet" {}
variable "vnet_rg" {}
variable "Machine_Type" {}
variable "EmailAddress" {}
variable "ExpirationDate" {}


variable "vm_size" {
  type = string
  default = "Standard_D4ds_v5"
}

variable "vm_timezone" {
  type = string
  default = "W. Europe Standard Time"  
}

variable "storage_account_type" {
  type    = string
  default = "StandardSSD_LRS"
}
variable "client_id" {
  description = "The client ID for Azure authentication"
  type        = string
}

variable "client_secret" {
  description = "The client secret for Azure authentication"
  type        = string
}

variable "tenant_id" {
  description = "The tenant ID for Azure authentication"
  type        = string
}
