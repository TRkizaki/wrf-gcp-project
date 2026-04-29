# 4. Experimental Design

## 4.1 Workload

We use the WRF idealized supercell case `em_quarter_ss` for all experiments. This case:

- Has a fixed 41x41x40 grid with 250 m horizontal spacing.
- Runs serial (`./wrf.exe`, no `mpirun`) by default.
- Produces deterministic output across runs of identical configuration.
- Has a typical wall-clock runtime of 30-90 seconds for a 60-minute simulated period on commodity cloud VMs.

**Why idealized.** The idealized case removes external-data dependencies (no WPS/ERA5 download), giving us a stable, reproducible workload to characterize the *infrastructure*. Real-data cases (e.g., precipitation forecasting for Ohrid) are deferred to future work (Section 7).

## 4.2 Primary Matrix (2x2)

We vary two factors:

| Factor | Levels |
|---|---|
| `machine_type` | `e2-standard-2` (2 vCPU, 8 GB), `e2-standard-4` (4 vCPU, 16 GB) |
| `use_spot` | `true` (Spot), `false` (on-demand) |

Producing four cells. For each cell, we measure:

- `t_setup_s`, `t_build_s`, `t_run_s`, `t_upload_s`, `t_total_s`
- `t_wrf_s` (inside-container `wrf.exe` wallclock)
- Output size (constant: 116 MiB `wrfout`, 253 MiB `wrfinput`)
- Realized cost: `cost_est_usd = (t_total_s / 3600) * hourly_usd`

GCP `e2-standard-*` pricing (europe-west1, retrieved during experiment campaign):

| machine | on-demand | spot |
|---|---|---|
| e2-standard-2 | $0.067/hr | $0.020/hr |
| e2-standard-4 | $0.134/hr | $0.040/hr |

## 4.3 Variance Characterization

After observing a 38 vs 66 second discrepancy in `t_wrf_s` between the original baseline run and the on-demand row of the matrix (both `e2-standard-2`), we initiated a variance study with a target of n=3 cold-boot replicates of the `e2-standard-2 + spot` configuration.

**Achieved n=2** (one original baseline + one replicate). The third and fourth replicates were not collected: the GCP free-trial billing window expired during the experimental campaign, terminating the active VM mid-build and disabling further compute API access.

**Implication.** The variance characterization reported in Section 5.4 is preliminary. Future work (Section 7) should extend to n>=3 per cell with a paid billing account.

## 4.4 Reproducibility Protocol

Each experiment is a complete cold boot:

1. `terraform.tfvars` is set to the target `(machine_type, use_spot)` pair.
2. `terraform apply -auto-approve` provisions all six resources.
3. The VM's metadata startup script auto-executes the full pipeline (Section 3.4).
4. `summary.json` is fetched from GCS and appended to `results/experiments.csv`.
5. `terraform destroy -auto-approve` removes all resources.
6. The CSV row is committed to git with the run ID.

Every row in `results/experiments.csv` corresponds to one git commit on the `feat/experiment-instrumentation` branch, allowing reviewers to checkout any historical state.

## 4.5 Threats to Validity

> Brief preview; full discussion in Section 6.

1. **Single zone** (`europe-west1-b`): variance from cross-zone host heterogeneity not captured.
2. **Shared-core machine family** (e2): "burstable" CPUs introduce noise that dedicated families (n2-standard-*) would not.
3. **Single workload** (`em_quarter_ss`): findings about vCPU scaling on serial workloads may not generalize to MPI-parallel real-data WRF.
4. **One run per cell** (except partial variance study): n=1 is below the threshold for confident inference.
