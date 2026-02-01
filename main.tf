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
  description = "GCP region"
  type        = string
  default     = "europe-west1"
}

variable "wrf_run_minutes" {
  description = "WRF simulation duration in minutes"
  type        = number
  default     = 60
}

variable "wrf_case" {
  description = "WRF idealized case name"
  type        = string
  default     = "em_quarter_ss"
}

variable "use_spot" {
  description = "Use Spot VM (preemptible) for cost savings"
  type        = bool
  default     = false
}

variable "machine_type" {
  description = "GCE machine type"
  type        = string
  default     = "e2-standard-2"
}

# -------------------------
# Enable required APIs
# -------------------------
resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

# -------------------------
# GCS bucket for WRF input/output
# -------------------------
resource "google_storage_bucket" "wrf_data" {
  name     = "${var.project_id}-wrf-data"
  location = var.region

  uniform_bucket_level_access = true
  force_destroy               = true
}

output "bucket_name" {
  value = google_storage_bucket.wrf_data.name
}

# -------------------------
# Service account for VM
# -------------------------
resource "google_service_account" "vm_sa" {
  account_id   = "wrf-vm-sa"
  display_name = "WRF VM Service Account"
}

resource "google_storage_bucket_iam_member" "wrf_bucket_writer" {
  bucket = google_storage_bucket.wrf_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.vm_sa.email}"
}

# -------------------------
# Compute Engine VM (WRF runner)
# -------------------------
resource "google_compute_instance" "wrf_runner" {
  name         = "${var.project_id}-wrf-runner"
  machine_type = var.machine_type
  zone         = "${var.region}-b"

  depends_on = [
    google_project_service.compute,
    google_project_service.storage
  ]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 50  # Increased for Docker image build
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  service_account {
    email  = google_service_account.vm_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # Spot VM configuration
  scheduling {
    preemptible                 = var.use_spot
    automatic_restart           = var.use_spot ? false : true
    on_host_maintenance         = var.use_spot ? "TERMINATE" : "MIGRATE"
    provisioning_model          = var.use_spot ? "SPOT" : "STANDARD"
    instance_termination_action = var.use_spot ? "STOP" : null
  }

  # Metadata for WRF configuration
  metadata = {
    wrf-run-minutes = var.wrf_run_minutes
    wrf-case        = var.wrf_case
    gcs-bucket      = google_storage_bucket.wrf_data.name
    enable-oslogin  = "TRUE"
  }

  metadata_startup_script = file("${path.module}/scripts/startup.sh")

  labels = {
    app      = "wrf-runner"
    wrf-case = var.wrf_case
    spot     = var.use_spot ? "true" : "false"
  }
}

output "vm_name" {
  value = google_compute_instance.wrf_runner.name
}

output "vm_zone" {
  value = google_compute_instance.wrf_runner.zone
}

output "ssh_command" {
  value = "gcloud compute ssh ${google_compute_instance.wrf_runner.name} --zone ${google_compute_instance.wrf_runner.zone}"
}

output "spot_enabled" {
  value = var.use_spot
}
