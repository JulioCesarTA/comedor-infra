terraform {
  required_version = ">= 1.6"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.6" }
  }
}

variable "project" {}
variable "region"  { default = "us-central1" }

provider "google" {
  project = var.project
  region  = var.region
}

# ---------- GKE ----------
resource "google_container_cluster" "gke" {
  name                     = "gke-comedor"
  location                 = var.region
  initial_node_count       = 2
  remove_default_node_pool = false
  deletion_protection      = false
  workload_identity_config { workload_pool = "${var.project}.svc.id.goog" }
  node_config {
    machine_type = "e2-standard-2"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

# ---------- Cloud SQL Postgres (pagos) ----------
resource "google_sql_database_instance" "pagos" {
  name             = "pagos-pg"
  database_version = "POSTGRES_16"
  region           = var.region
  settings {
    tier      = "db-f1-micro"
    disk_size = 20
  }
  deletion_protection = false
}

resource "google_sql_database" "db" {
  name     = "pagos_tickets"
  instance = google_sql_database_instance.pagos.name
}

# ---------- Artifact Registry ----------
resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = "comedor-uagrm"
  format        = "DOCKER"
}

# ---------- Service Account (Workload Identity) ----------
resource "google_service_account" "pagos" {
  account_id   = "pagos-sa"
  display_name = "pagos-tickets-service"
}

output "cluster_name" { value = google_container_cluster.gke.name }
output "gar_registry" { value = "${var.region}-docker.pkg.dev/${var.project}/comedor-uagrm" }
