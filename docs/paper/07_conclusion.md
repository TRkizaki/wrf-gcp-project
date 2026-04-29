# 7. Conclusion and Future Work

## 7.1 Summary

We presented an Infrastructure-as-Code pipeline for deploying the WRF model on Google Cloud Platform, compiled from source inside a CentOS-7 container and orchestrated through a single `terraform apply`. Across a 2x2 cost-performance matrix on the `em_quarter_ss` idealized supercell case, we observed:

1. Additional vCPUs accelerate the WRF source build by ~23% (1456 s → 1124 s) but provide no benefit to the serial `wrf.exe` workload itself (66 s vs 68 s, within noise).
2. Spot-VM economics are favorable for short successful runs but flip negative under preemption — one preempted Spot run cost ~37% more than the equivalent on-demand run.
3. Persistent-disk Docker image caching enables Spot recovery in under 90 seconds with no application-level checkpointing logic, a methodological pattern of broader interest for cost-aware cloud HPC.

The complete experimental campaign cost USD $0.16 and ~75 minutes of wallclock, demonstrating that cloud-based WRF experimentation is financially trivial at this scale.

## 7.2 Future Work

### 7.2.1 Variance Characterization (Highest Priority)

Extend each matrix cell to n>=3 cold-boot replicates with paid billing. Add a third level of `machine_type` (`n2-standard-2`, dedicated cores) to isolate e2 shared-core variance from real per-call variance.

### 7.2.2 MPI Scaling Study

The current pipeline runs `wrf.exe` serial. Modifying the startup script to invoke `mpirun -np N ./wrf.exe` with appropriate `nproc_x` / `nproc_y` in the namelist would produce a real strong-scaling curve. The `em_quarter_ss` grid is small (41x41) but supports decomposition up to ~4 ranks; larger idealized cases (`em_les`, `em_b_wave`) would extend the curve.

### 7.2.3 Real-Data Case (Ohrid Precipitation)

The original motivation was precipitation forecasting for the Ohrid area. This requires:
- WPS preprocessing (`geogrid.exe`, `ungrib.exe`, `metgrid.exe`)
- ERA5 boundary conditions (via Climate Data Store API)
- Domain configuration matching the Ohrid geography
- Visualization pipeline (NCL or Python+xarray)

Each adds methodology surface area but is achievable on the same IaC foundation. A pre-built image hosted in Artifact Registry would amortize the ~20-min build cost across many real-data experiments.

### 7.2.4 Pre-Warmed Image in Artifact Registry

Push `wrf_ideal:em_quarter_ss` (and future `wrf_real:*` variants) to Google Artifact Registry once. Modify the startup script to `docker pull` instead of `docker build`. This collapses every subsequent run to ~2-3 minutes, making the marginal cost of an experiment ~$0.001.

### 7.2.5 Cross-Cloud Portability

Refactor the Terraform configuration into a provider-agnostic module structure with `aws/`, `azure/`, and `gcp/` implementations. Re-run the matrix on AWS Spot and Azure Spot to compare preemption behavior and pricing models. This would directly extend Section 5.4's persistent-disk-cache observation across providers.

### 7.2.6 Marker File Refactor

The `MARKER_FILE` (`/opt/.wrf_setup_complete`) in `scripts/startup.sh` is currently `touch`'d only after Docker build success, despite gating the apt-get install phase. Splitting into two markers (`/opt/.deps_installed`, `/opt/.image_built`) would correctly express the dependencies and improve recovery semantics.

## 7.3 Closing

For practitioners considering cloud-based atmospheric modeling: the cost is much lower than reputation suggests, the reproducibility story is much stronger than ad-hoc workstation deployments, and the pipeline patterns we describe are not WRF-specific. We hope this paper contributes a usable template for graduate students and small research groups newly entering cloud HPC.

**Artifact availability.** All code and data are available at `https://github.com/TRkizaki/wrf-gcp-project`, with the `feat/experiment-instrumentation` branch containing the exact state used for this paper.
