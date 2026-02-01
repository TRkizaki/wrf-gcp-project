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

# WRF container image (for step A: pull + check wrf.exe exists)
variable "wrf_image" {
  description = "WRF container image"
  type        = string
  default     = "ghcr.io/uomresearchit/wrf-wps:3.9.1.1"
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

# Allow VM to write objects to the WRF bucket
resource "google_storage_bucket_iam_member" "wrf_bucket_writer" {
  bucket = google_storage_bucket.wrf_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.vm_sa.email}"
}

# -------------------------
# Compute Engine VM (runner)
# -------------------------
resource "google_compute_instance" "wrf_runner" {
  name         = "${var.project_id}-wrf-runner"
  machine_type = "e2-standard-2"
  zone         = "${var.region}-b"

  depends_on = [
    google_project_service.compute,
    google_project_service.storage
  ]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30
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

  # IMPORTANT:
  # - Terraform will try to interpolate ${...} inside heredoc.
  # - For bash variables, use $${VAR} to pass through literally.
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    export DEBIAN_FRONTEND=noninteractive

    BUCKET="${google_storage_bucket.wrf_data.name}"
    WRF_IMAGE="${var.wrf_image}"

    TS="$(date -u +%Y%m%dT%H%M%SZ)"
    HOST="$(hostname)"
    RUN_DIR="/opt/wrf_check"

    mkdir -p "$${RUN_DIR}/logs"
    chmod -R 777 "$${RUN_DIR}"

    echo "=== WRF check on $${HOST} at $${TS} ===" | tee "$${RUN_DIR}/logs/startup-$${TS}.log"
    echo "Image: $${WRF_IMAGE}" | tee -a "$${RUN_DIR}/logs/startup-$${TS}.log"

    # Install Docker + deps
    apt-get update
    apt-get install -y ca-certificates curl gnupg apt-transport-https lsb-release docker.io

    systemctl enable --now docker
    docker version | tee -a "$${RUN_DIR}/logs/startup-$${TS}.log"

    # Install Google Cloud CLI (for gcloud storage cp)
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor -o /etc/apt/keyrings/google-cloud.gpg

    echo "deb [signed-by=/etc/apt/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
      > /etc/apt/sources.list.d/google-cloud-sdk.list

    apt-get update
    apt-get install -y google-cloud-cli

    # Pull image
    docker pull "$${WRF_IMAGE}" | tee -a "$${RUN_DIR}/logs/pull-$${TS}.log"

    # Find wrf.exe inside container
    echo "Searching for wrf.exe..." | tee -a "$${RUN_DIR}/logs/startup-$${TS}.log"
    docker run --rm "$${WRF_IMAGE}" sh -lc '
      set -eu
      echo "PATH=$PATH"
      for p in /WRF/main/wrf.exe /wrf/WRF/main/wrf.exe /opt/WRF/main/wrf.exe; do
        if [ -x "$p" ]; then
          echo "FOUND: $p"
          ls -la "$p"
          exit 0
        fi
      done
      FOUND="$(find / -name wrf.exe -type f 2>/dev/null | head -n 20 || true)"
      if [ -n "$FOUND" ]; then
        echo "FOUND (via find):"
        echo "$FOUND"
        exit 0
      fi
      echo "NOT FOUND: wrf.exe"
      exit 2
    ' | tee -a "$${RUN_DIR}/logs/wrfexe-$${TS}.log"

    # Upload logs to GCS
    OUT_PATH="gs://$${BUCKET}/checks/$${HOST}/$${TS}/"
    gcloud storage cp -r "$${RUN_DIR}/logs/*" "$${OUT_PATH}logs/" || true

    echo "DONE. Logs uploaded to $${OUT_PATH}" | tee -a "$${RUN_DIR}/logs/startup-$${TS}.log"
  EOT

  labels = {
    app = "wrf-runner"
  }
}

output "vm_name" {
  value = google_compute_instance.wrf_runner.name
}






