terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.3" }
  }
}
provider "azurerm" { features {} }

variable "location" { default = "eastus" }
variable "project"  { default = "comedor-uagrm" }

resource "azurerm_resource_group" "rg" {
  name     = "${var.project}-rg"
  location = var.location
}

# ---------- AKS ----------
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-comedor"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks-comedor"
  kubernetes_version  = "1.30"

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_D2s_v3"
  }

  identity { type = "SystemAssigned" }
  workload_identity_enabled = true
  oidc_issuer_enabled       = true
}

# ---------- PostgreSQL Flexible Server (comensales) ----------
resource "azurerm_postgresql_flexible_server" "pg" {
  name                   = "${var.project}-pg"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = var.location
  version                = "16"
  administrator_login    = "comedoradmin"
  administrator_password = "ReemplazarEnKeyVault!"
  sku_name               = "B_Standard_B1ms"
  storage_mb             = 32768
  zone                   = "1"
}

resource "azurerm_postgresql_flexible_server_database" "db" {
  name      = "comensales_reservas"
  server_id = azurerm_postgresql_flexible_server.pg.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

# ---------- Key Vault ----------
resource "azurerm_key_vault" "kv" {
  name                = "${var.project}-kv"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
}

data "azurerm_client_config" "current" {}

# ---------- ACR ----------
resource "azurerm_container_registry" "acr" {
  name                = "comedorregistry"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  sku                 = "Standard"
}

output "aks_name" { value = azurerm_kubernetes_cluster.aks.name }
output "acr_name" { value = azurerm_container_registry.acr.name }
