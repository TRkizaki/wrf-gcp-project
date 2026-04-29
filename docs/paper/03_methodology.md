# 3. Methodology

This section describes the pipeline's three layers — infrastructure, container, and automation — together with the observability artifacts that make each run self-describing. Throughout, we emphasize choices that trade short-term convenience for long-term reproducibility, and that keep the operator's interface to a single Terraform invocation.

## 3.1 Design Goals

Four constraints shaped every design decision:

1. **One-command provisioning.** `terraform apply` produces a working WRF environment from a clean GCP project, with no manual console steps.
2. **One-command teardown.** `terraform destroy` removes every billable resource the run created, eliminating the "forgotten VM" failure mode common in ad-hoc cloud experiments.
3. **Self-documenting artifacts.** Each output written to GCS carries enough metadata to reconstruct the configuration that produced it, without reference to local notes or shell history.
4. **Minimum-trust security.** The VM's runtime identity is a service account scoped to a single bucket; no static keys are issued, and no broader project privileges are granted.

These goals are not independent: self-documenting artifacts are only meaningful if the provisioning step is deterministic, and minimum-trust security is only enforceable when the IaC layer owns IAM bindings.

## 3.2 Infrastructure-as-Code Layer

The Terraform configuration (`main.tf`, ~165 lines) declares six resources, summarized in Table 1.

| Resource | Role |
|---|---|
| `google_project_service.compute` | Enables the Compute Engine API |
| `google_project_service.storage` | Enables the Cloud Storage API |
| `google_storage_bucket.wrf_data` | Holds inputs, outputs, and run metadata |
| `google_service_account.vm_sa` | VM identity, no static keys |
| `google_storage_bucket_iam_member.wrf_bucket_writer` | `roles/storage.objectAdmin` scoped to the bucket |
| `google_compute_instance.wrf_runner` | Debian 12 VM, configurable machine type and Spot flag |

**Table 1.** Terraform-managed resources. The IAM binding is bucket-scoped rather than project-scoped, satisfying design goal 4.

Per-experiment configuration is parameterized through `terraform.tfvars`, so that switching cells of the experimental matrix (Section 4) requires editing two lines:

```hcl
project_id      = "..."
region          = "europe-west1"
machine_type    = "e2-standard-2"     # or e2-standard-4
use_spot        = true                # or false for on-demand
wrf_case        = "em_quarter_ss"
wrf_run_minutes = 60
```

> TODO: include a figure showing the resource graph (`terraform graph | dot -Tpng > resource_graph.png`).

## 3.3 Container Layer

WRF is compiled from source inside a CentOS-7 container at deploy time. The Dockerfile, embedded in `scripts/startup.sh` to keep the repository to a single source of truth, installs the required toolchain:

- `gcc`, `gcc-gfortran`, `gcc-c++` (4.8.5)
- `netcdf-devel`, `netcdf-fortran-devel`, `hdf5-devel`
- `openmpi`, `openmpi-devel`

It then downloads WRF 4.0.3, executes `./configure` with options 34/1 (gfortran, distributed-memory build), and compiles the `em_quarter_ss` idealized supercell case.

**Design decision: source compile vs prebuilt image.** A prebuilt image such as `ghcr.io/uomresearchit/wrf-wps:3.9.1.1` would eliminate the ~20-minute compile, but binds the experiment to one publisher's image lifecycle and one WRF version. Compiling from source is reproducible from any future checkout, makes every dependency visible to the reader, and exposes the full toolchain for inspection. The compile cost is amortizable by pushing the resulting image to Google Artifact Registry once the toolchain stabilizes (Section 7.2.4); we deliberately defer that optimization to keep the present pipeline auditable end-to-end.

## 3.4 Automation Flow

The metadata startup script (`scripts/startup.sh`, ~230 lines) executes on every VM boot and orchestrates the full lifecycle:

1. **Configuration.** Reads runtime parameters from the GCE metadata server (`wrf-case`, `wrf-run-minutes`, `gcs-bucket`, `machine-type`, `use-spot`), so the same script behaves correctly across all matrix cells without code changes.
2. **First-boot setup.** Installs Docker and the `gcloud` CLI, gated by the `/opt/.wrf_setup_complete` marker so that a recovered Spot VM skips re-installation (a property exploited in Section 5.4).
3. **Image build.** Builds the WRF Docker image if no cached layer satisfies the build, otherwise reuses the persistent-disk Docker cache.
4. **Run.** Inside the container, links the WRF support files, runs `ideal.exe` to generate initial conditions, patches `namelist.input` for the requested duration, and invokes `wrf.exe`.
5. **Upload.** Captures every output artifact and uploads it to `gs://<bucket>/runs/<TS>-<case>-<minutes>min/` under a timestamped run directory.
6. **Summary.** Emits `summary.json`, containing the timing breakdown, run identifiers, and configuration parameters.

The script records five wallclock markers to decompose total runtime by phase:

`T_SCRIPT_START → T_SETUP_END → T_BUILD_END → T_RUN_END → T_UPLOAD_END`

These yield `t_setup_s`, `t_build_s`, `t_run_s`, `t_upload_s`, and `t_total_s` in the per-run summary. The decomposition is the foundation for the cost-attribution analysis in Section 5: without separating build time from run time, on-demand and Spot economics cannot be compared meaningfully.

> TODO: include a sequence diagram of the boot-to-upload flow.

## 3.5 Observability and Artifact Layout

Each run produces seven artifacts in the run-specific GCS prefix:

- `wrfout_d01_0001-01-01_00:00:00` — primary forecast output (~116 MiB)
- `wrfinput_d01` — initial conditions used by `wrf.exe` (~253 MiB)
- `namelist.input` — the exact namelist applied to this run (~5 KiB)
- `rsl.out.0000`, `rsl.error.0000` — WRF runtime logs
- `elapsed_seconds.txt` — `wrf.exe` integration time, integer seconds
- `summary.json` — complete machine-readable run metadata

`summary.json` is the single source of truth for the experimental dataset: one file per run translates directly to one row of `results/experiments.csv` (Section 4). Because the summary records the machine type, Spot flag, and case alongside the timings, no out-of-band bookkeeping is required to reconstruct which configuration produced which numbers — a property that becomes critical when reruns and preemption events are interleaved across multiple sessions.
