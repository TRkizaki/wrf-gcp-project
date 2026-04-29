# 6. Discussion

## 6.1 Implications for Cloud HPC Practice

Our results suggest three operational guidelines for small-scale cloud-WRF practitioners:

1. **Match vCPU count to the dominant phase of work.** If most wallclock is spent in `./compile`, more cores help. If most is spent in `wrf.exe` (serial or with limited domain decomposition), they do not. Practitioners running many short jobs against a pre-built image should size for the *runtime*; practitioners deploying fresh from source should consider transient large-VM provisioning for the build phase.

2. **Spot is not free money.** For workloads where one full attempt fits within typical preemption windows (~30-60 minutes in our observation), Spot provides genuine cost savings. For longer builds, the expected wasted time per preemption can exceed the price advantage.

3. **Persistent disks are implicit checkpoints.** The Docker layer cache surviving Spot reclamation is an underappreciated property. Pipelines designed around `docker image inspect` gates (rather than rebuild-on-every-boot) gain Spot resilience for free.

## 6.2 Threats to Validity

### Internal validity

- **n=1 per matrix cell.** With a single observation per cell, our cost and timing comparisons rest on point estimates, not distributions. Section 5.5 reports a partial n=2 variance study.
- **e2 burst variance.** The shared-core e2 family exhibits inherent noise that we have not quantified. A repeat on `n2-standard-*` would isolate this.
- **Single zone.** All experiments ran in `europe-west1-b`. Cross-zone variance is unknown.
- **Single calendar window.** Spot preemption rates vary by demand; our 1/3 preemption rate is a snapshot, not a long-run estimate.

### External validity

- **One workload (`em_quarter_ss`).** This is an idealized, small-grid, serial case. Real-data WRF runs (e.g., a precipitation forecast for Ohrid) involve WPS preprocessing, larger grids, MPI parallelism, and potentially I/O-bound output writing. Findings about vCPU scaling and Spot resilience would need re-examination at that scale.
- **One container path (source-compile).** A pre-built-image strategy would have a very different cost-time profile (no t_build phase to amortize).
- **One cloud provider.** Findings about Spot specifically may differ on AWS Spot or Azure Spot, which have different preemption notification windows and pricing structures.

## 6.3 Limitations from the Experimental Campaign

The free-trial billing window of the GCP project expired during data collection, terminating the rep 2/3 attempt mid-build and preventing reps 3/3 and the on-demand variance reps. We treat this as itself a finding about cloud-experiment cost discipline:

> Even small-scale cloud HPC experiments can hit billing constraints unexpectedly. Reproducibility artifacts (this paper's `experiments.csv`, `main.tf`, and git history) must be designed to be valuable independent of the original cloud account's continued availability.

Our `experiments.csv` is fully self-contained; readers can reproduce the dataset on any GCP project (paid or trial) by checking out the corresponding git commit and running `terraform apply`.

## 6.4 What This Paper Does Not Claim

We are explicit about scope:

- We do **not** claim a meteorological contribution. The `em_quarter_ss` case is stock; we did not modify physics or initial conditions.
- We do **not** claim that GCP is superior to AWS or Azure for cloud-WRF. We chose GCP for free-trial credits and Terraform tooling familiarity.
- We do **not** claim n-of-1 cost figures generalize to other cases. They quantify *this* configuration on *this* case during *this* campaign.

The contribution is the **methodology and the artifact**: a fully reproducible, cost-instrumented, IaC-driven WRF deployment pattern that future work — by us or others — can extend to richer experimental matrices.
