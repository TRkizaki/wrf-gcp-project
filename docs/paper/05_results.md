# 5. Results

## 5.1 Dataset

Five successful runs were collected: four 2x2 matrix cells and one variance replicate. Total experimental cost: **$0.16**. Total experimental wallclock: **~75 minutes**.

| run | date | machine | spot | t_setup | t_build | t_run | t_wrf | t_total | $ |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-04-27 | std-2 | ✓ | — | — | — | 38 | 1085 | 0.006 |
| 2 | 2026-04-27 | std-2 | ✗ | 52 | 1456 | 71 | 66 | 1600 | 0.030 |
| 3 | 2026-04-28 | std-4 | ✓ | 0* | 1* | 69 | 64 | 75* | 0.052 |
| 4 | 2026-04-29 | std-4 | ✗ | 52 | 1124 | 72 | 68 | 1256 | 0.047 |
| rep1 | 2026-04-29 | std-2 | ✓ | 51 | 1422 | 71 | 66 | 1551 | 0.009 |

\* Row 3 was preempted at minute 76 of build; restart leveraged cached Docker image (see Section 5.5).

All times in seconds. Cost in USD. Output `wrfout_d01_0001-01-01_00:00:00` was bit-identical (121,314,219 bytes) across all runs, confirming workload determinism.

## 5.2 Finding 1 — Additional vCPUs Accelerate the Build, Not the Workload

Comparing rows 2 and 4 (both on-demand, same case, only `machine_type` differs):

| | std-2 | std-4 | delta |
|---|---|---|---|
| t_build_s | 1456 | 1124 | -23% |
| t_wrf_s | 66 | 68 | +3% (within noise) |

WRF's `./compile` invokes `make -j` and benefits from extra cores. `wrf.exe` for `em_quarter_ss` runs serial (no `mpirun`, no domain decomposition) and shows no benefit from additional cores.

> TODO: include `figures/fig3_build_vs_vcpu.png` — bar chart of t_build_s per machine type.

**Implication for cloud WRF deployments:** for production workloads, the choice of vCPU count must align with the parallelism of the *runtime* not just the build. A 4-vCPU VM is wasted on a serial WRF run; conversely, a 2-vCPU VM is suboptimal for compile.

## 5.3 Finding 2 — Spot Economics Flip Under Preemption

The spot-on-demand cost ratio for `e2-standard-*` is approximately 1:3.3. For successful runs without preemption (rows 1, rep1), Spot delivers near-to-nominal savings.

However, **row 3** (e2-standard-4 spot) was preempted at approximately minute 76 of the WRF source build. Recovery via `gcloud compute instances start` succeeded, but the realized cost was:

```
billed_hours = 76 min (wasted) + ~2 min (successful) = 78 min = 1.30 hr
cost_realized = 1.30 hr * $0.040/hr = $0.052
cost_if_on-demand = (~17 min) * $0.134/hr = ~$0.038
```

That is, **the preempted Spot run cost ~37% more than the equivalent on-demand run would have**.

> TODO: include `figures/fig1_cost_per_run.png` — bar chart of cost_est_usd per run, with row 3 highlighted.

**Implication:** Spot economics are favorable only if `P(preemption) * E[wasted_time]` is small relative to nominal price advantage. For builds longer than typical preemption windows (~1 hour in europe-west1 during this campaign), Spot may be net-negative without explicit checkpointing.

## 5.4 Finding 3 — Persistent-Disk Docker Cache Enables Sub-90s Spot Recovery

When row 3's preempted VM was restarted via `gcloud compute instances start`, the boot disk persisted unchanged. The startup script's idempotent gates produced an unexpected behavior:

- `apt-get install` was a no-op (~0 s) because Debian packages were already on disk.
- The Docker daemon found the in-progress build's intermediate layers in `/var/lib/docker`, and `docker image inspect wrf_ideal:em_quarter_ss` succeeded — though the original build had been killed before completion.

> TODO: investigate whether the cached image was truly the previously-failed build resumed, or whether Docker had committed an intermediate image. Check by comparing image SHA across runs.

The result: **t_total_s dropped from an expected ~1100 s (full cold rebuild) to 75 s** on the second boot. The marginal compute cost of the recovery was ~$0.001.

**This is a methodologically significant finding for cost-aware cloud HPC.** The persistent boot disk acts as an implicit checkpoint for any container-based workflow, with no application-level changes required. The pattern generalizes: pre-warm a persistent disk image, then iterate cheaply on Spot VMs that mount it.

## 5.5 Variance Characterization (Preliminary)

For the `e2-standard-2 + spot` configuration, observed `t_wrf_s` values across n=2 replicates plus the related on-demand row 2:

| run | spot | t_wrf_s |
|---|---|---|
| 1 (original) | ✓ | 38 |
| rep 1/3 | ✓ | 66 |
| 2 (on-demand) | ✗ | 66 |

Run 1's 38 s appears anomalous; rep 1/3 and row 2 agree at 66 s. Without n>=3, we cannot distinguish "true mean ≈ 66 s with row 1 outlier from low-load host scheduling" from "high inherent variance on e2 shared-core hardware."

> TODO: rerun with n>=3 once paid billing is available, and ideally repeat on `n2-standard-2` (dedicated cores) to isolate the e2-burst-noise contribution.
