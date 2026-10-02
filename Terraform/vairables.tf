variable "subscription_id" {
  type = string
}
variable "location" {
  type = string
}
variable "linux_vms" {
  type = map(object({
    name                 = string
    size                 = string
    disk_size_gb         = number
    storage_account_type = string
    subnet_key           = string
  }))
}
variable "rg-lab" {
  type = string
}
variable "rg-sa" {
  type = string
}
variable "image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}
variable "admin_username" {
  type = string
}
variable "public_key" {
  type = string
}
variable "vnet_name" {
  type = string
}

variable "vnet_address_space" {
  type = list(string)
}

variable "subnets" {
  type = map(object({
    name             = string
    address_prefixes = list(string)
  }))
}

variable "sa-tfstate" {
  type = string
}
variable "container-tfstate" {
  type = string
}

variable "db-disk" {
  type = number

}
variable "macip" {
  type = string
}