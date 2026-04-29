# 8. Reproducibility Appendix

## 8.1 Software Versions

| Component | Version |
|---|---|
| Terraform | 1.14.4 |
| `hashicorp/google` provider | ~> 5.0 |
| WRF (in container) | 4.0.3 |
| Container OS | CentOS 7 (`vault.centos.org` mirrors) |
| Compiler | gcc/gfortran 4.8.5-44.el7 |
| MPI | OpenMPI (system package, used at compile time only; runtime is serial) |
| Host OS (VM) | Debian 12 |
| Region / zone | `europe-west1` / `europe-west1-b` |

## 8.2 Reproducing the Full Dataset

Starting from a clean checkout and a GCP project with billing enabled:

```bash
git clone https://github.com/TRkizaki/wrf-gcp-project.git
cd wrf-gcp-project
git checkout feat/experiment-instrumentation

# 1. Configure
cp terraform.tfvars.example terraform.tfvars   # if .example exists, else edit terraform.tfvars
# Edit project_id to your GCP project
# Set machine_type and use_spot for the desired cell

# 2. Authenticate
gcloud auth application-default login
gcloud config set project <YOUR_PROJECT>

# 3. Per-experiment-cell loop:
for cell in "e2-standard-2 true" "e2-standard-2 false" "e2-standard-4 true" "e2-standard-4 false"; do
    read MT SPOT <<< "$cell"
    # Edit terraform.tfvars: set machine_type="$MT" and use_spot=$SPOT
    terraform apply -auto-approve
    # Wait for run to complete (poll GCS for new run dir + summary.json)
    # Append summary.json data to results/experiments.csv
    terraform destroy -auto-approve
done
```

Each cell takes ~18-25 minutes wallclock (cold boot + compile + run + upload). Total ~2 hours for the 4-cell matrix.

## 8.3 Per-Run Verification

For any single run, verify success by:

```bash
# 1. WRF reported success
gcloud storage cat gs://<bucket>/runs/<run_id>/rsl.out.0000 | tail -5
# expect: "wrf: SUCCESS COMPLETE WRF"

# 2. Output is the expected size
gcloud storage ls -L gs://<bucket>/runs/<run_id>/wrfout_d01_0001-01-01_00:00:00 | grep Content-Length
# expect: 121314219

# 3. Timing is captured
gcloud storage cat gs://<bucket>/runs/<run_id>/summary.json
```

## 8.4 Git Commits Corresponding to Dataset Rows

Every row in `results/experiments.csv` traces to a specific commit on `feat/experiment-instrumentation`:

| Row | Commit | Description |
|---|---|---|
| Instrumentation foundation | `e580b2d` | Adds timing markers, CSV schema, and row #1 baseline |
| Row #2 (std-2 on-demand) | `e12fc14` | First clean instrumented run |
| Row #3 (std-4 spot, preempted) | `f35035e` | Preemption + recovery event |
| Row #4 (std-4 on-demand) | `620e9c6` | Matrix complete |
| Variance rep 1/3 | `39c255c` | Confirms row #1 was outlier |

Reviewers can `git checkout <commit>` to inspect the exact code and CSV state at any point in the campaign.

## 8.5 Cost Audit

Total realized spend during the experimental campaign (from GCP billing reports during free-trial period):

| Item | Cost |
|---|---|
| Compute (4 matrix runs + 1 variance rep + 1 preempted attempt) | ~$0.135 |
| Cloud Storage (transient, ~370 MiB ephemeral per run) | < $0.01 |
| Network egress (within-region, free) | $0.00 |
| **Total** | **~$0.16** |

The free-trial credit balance was sufficient to fund the entire campaign, with the trial expiring shortly after (a coincidence of timing, not a credit-exhaustion event).

## 8.6 Known Issues for Future Reproducers

1. **CentOS 7 mirror availability.** Our Dockerfile pins to `vault.centos.org` because the standard CentOS 7 mirrors went EOL in mid-2024. Future image rebuilds may require further mirror adjustments or migration to AlmaLinux/Rocky 8.
2. **GitHub WRF 4.0.3 tarball URL.** `https://github.com/wrf-model/WRF/archive/v4.0.3.tar.gz` was stable during this campaign. WRF release URL conventions have changed across major versions; using a newer WRF (4.4+) would require Dockerfile adjustments.
3. **`docker.io` vs Docker CE.** We use Debian's `docker.io` package for simplicity. Production deployments should use the official Docker CE repo for newer features and security updates.
