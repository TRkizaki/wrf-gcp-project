# 3. Methodology

## 3.1 Design Goals

The pipeline is designed to satisfy four simultaneous constraints:

1. **One-command provisioning** — `terraform apply` produces a working WRF environment from a clean GCP project.
2. **One-command teardown** — `terraform destroy` removes all billable resources.
3. **Self-documenting artifacts** — every output in GCS includes the configuration that produced it.
4. **Minimum-trust security** — the VM identity (service account) has narrowly-scoped IAM (object-admin on one bucket only).

## 3.2 Infrastructure-as-Code Layer

The Terraform configuration (`main.tf`, ~165 lines) defines six resources:

| Resource | Role |
|---|---|
| `google_project_service.compute` | Enables the Compute Engine API |
| `google_project_service.storage` | Enables the Cloud Storage API |
| `google_storage_bucket.wrf_data` | Holds inputs, outputs, and run metadata |
| `google_service_account.vm_sa` | VM identity, no static keys |
| `google_storage_bucket_iam_member.wrf_bucket_writer` | `roles/storage.objectAdmin` scoped to the bucket |
| `google_compute_instance.wrf_runner` | Debian 12 VM, configurable machine type and Spot flag |

Configuration is parameterized via `terraform.tfvars`:

```hcl
project_id      = "..."
region          = "europe-west1"
machine_type    = "e2-standard-2"     # or e2-standard-4
use_spot        = true                # or false for on-demand
wrf_case        = "em_quarter_ss"
wrf_run_minutes = 60
```

> TODO: include a figure showing the resource graph. Can generate via `terraform graph | dot -Tpng > resource_graph.png`.

## 3.3 Container Layer

WRF is compiled from source inside a CentOS-7 container at deploy time. The Dockerfile (embedded in `scripts/startup.sh`) installs:

- `gcc`, `gcc-gfortran`, `gcc-c++` (4.8.5)
- `netcdf-devel`, `netcdf-fortran-devel`, `hdf5-devel`
- `openmpi`, `openmpi-devel`

…then downloads WRF 4.0.3, runs `./configure` (option 34/1 — gfortran, dmpar), and compiles `em_quarter_ss`.

**Design decision: source compile vs prebuilt image.** A prebuilt container (e.g., `ghcr.io/uomresearchit/wrf-wps:3.9.1.1`) would skip the ~20-minute compile but locks the image to one provider and one WRF version. Source compile is reproducible from any future point and demonstrates the full toolchain. The compile cost is amortizable via Artifact Registry (see Section 7 future work).

## 3.4 Automation Flow

The metadata startup script (`scripts/startup.sh`, ~230 lines) executes on every VM boot. It:

1. Reads runtime parameters from GCE metadata (`wrf-case`, `wrf-run-minutes`, `gcs-bucket`, `machine-type`, `use-spot`).
2. Installs Docker and `gcloud` CLI on first boot (gated by `/opt/.wrf_setup_complete` marker).
3. Builds the WRF Docker image if not cached.
4. Runs the container: links WRF support files, executes `ideal.exe` to generate initial conditions, patches `namelist.input` for the requested duration, runs `wrf.exe`.
5. Captures all outputs and uploads to `gs://<bucket>/runs/<TS>-<case>-<minutes>min/`.
6. Emits `summary.json` with timing breakdown and configuration metadata.

The script instruments five timing markers:
`T_SCRIPT_START → T_SETUP_END → T_BUILD_END → T_RUN_END → T_UPLOAD_END`

…producing `t_setup_s`, `t_build_s`, `t_run_s`, `t_upload_s`, `t_total_s` in `summary.json`. This decomposition is essential for the experiments in Section 5.

> TODO: include a sequence diagram of the boot-to-upload flow.

## 3.5 Observability and Artifact Layout

Every run produces seven artifacts in GCS:

- `wrfout_d01_0001-01-01_00:00:00` — primary output (~116 MiB)
- `wrfinput_d01` — initial conditions (~253 MiB)
- `namelist.input` — exact namelist used (~5 KiB)
- `rsl.out.0000`, `rsl.error.0000` — WRF runtime logs
- `elapsed_seconds.txt` — `wrf.exe` runtime, integer seconds
- `summary.json` — complete run metadata, machine-readable

The `summary.json` is the single source of truth for the experiments dataset (Section 4). One row of `results/experiments.csv` is produced per run.
