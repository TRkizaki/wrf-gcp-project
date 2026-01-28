terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  default = "europe-west1"
}

# GCS bucket for WRF input/output
resource "google_storage_bucket" "wrf_data" {
  name     = "${var.project_id}-wrf-data"
  location = var.region
  
  uniform_bucket_level_access = true
  force_destroy = true
}

output "bucket_name" {
  value = google_storage_bucket.wrf_data.name
}
