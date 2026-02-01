# WRF on GCP — Small-Scale HPC Project

> Running the Weather Research and Forecasting (WRF) model on Google Cloud Platform using Docker containers and Infrastructure as Code (Terraform)

![WRF](https://img.shields.io/badge/WRF-4.0.3-blue)
![Terraform](https://img.shields.io/badge/Terraform-1.14-purple)
![GCP](https://img.shields.io/badge/GCP-Compute%20Engine-orange)
![Docker](https://img.shields.io/badge/Docker-CentOS%207-blue)

##  Project Overview

| Item | Details |
|------|---------|
| **Objective** | Demonstrate how to run WRF on cloud infrastructure |
| **Duration** | 1 month |
| **Team Size** | 1 person |
| **Evaluation Criteria** | Execution time, Cost optimization, Reproducibility (IaC) |

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          LOCAL PC (Control Point)                        │
│                                                                          │
│   ┌──────────────┐     ┌──────────────┐     ┌──────────────┐           │
│   │   Terraform  │     │   gcloud     │     │    gsutil    │           │
│   │   (IaC)      │     │   (SSH)      │     │   (Storage)  │           │
│   └──────┬───────┘     └──────┬───────┘     └──────┬───────┘           │
└──────────│─────────────────────│─────────────────────│───────────────────┘
           │                     │                     │
           │    terraform apply  │   SSH monitoring    │  Download results
           ▼                     ▼                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        GOOGLE CLOUD PLATFORM                             │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                      Compute Engine VM                             │  │
│  │                      (e2-standard-2)                               │  │
│  │                                                                    │  │
│  │   ┌─────────────────────────────────────────────────────────────┐ │  │
│  │   │                    Docker Container                          │ │  │
│  │   │                    (CentOS 7 + WRF 4.0.3)                    │ │  │
│  │   │                                                              │ │  │
│  │   │   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    │ │  │
│  │   │   │  ideal.exe  │ -> │   wrf.exe   │ -> │   wrfout_*  │    │ │  │
│  │   │   │  (Init)     │    │ (Simulate)  │    │  (Output)   │    │ │  │
│  │   │   └─────────────┘    └─────────────┘    └─────────────┘    │ │  │
│  │   │                                                              │ │  │
│  │   └─────────────────────────────────────────────────────────────┘ │  │
│  │                                                                    │  │
│  │   Metadata:                                                        │  │
│  │   - wrf-run-minutes: 60                                           │  │
│  │   - wrf-case: em_quarter_ss                                       │  │
│  │   - gcs-bucket: project-xxx-wrf-data                              │  │
│  │                                                                    │  │
│  └────────────────────────────────┬──────────────────────────────────┘  │
│                                   │                                      │
│                                   │ gsutil cp                            │
│                                   ▼                                      │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                     Google Cloud Storage                           │  │
│  │                     (GCS Bucket)                                   │  │
│  │                                                                    │  │
│  │   gs://project-xxx-wrf-data/                                      │  │
│  │   ├── runs/                                                        │  │
│  │   │   ├── 20260201T181437Z-em_quarter_ss-60min/  (On-Demand)     │  │
│  │   │   │   ├── wrfout_d01_0001-01-01_00:00:00     (116 MB)        │  │
│  │   │   │   ├── wrfinput_d01                       (253 MB)        │  │
│  │   │   │   ├── namelist.input                                      │  │
│  │   │   │   ├── rsl.error.0000                                      │  │
│  │   │   │   ├── rsl.out.0000                                        │  │
│  │   │   │   └── summary.json                                        │  │
│  │   │   └── 20260201T191919Z-em_quarter_ss-60min/  (Spot VM)       │  │
│  │   │       └── ...                                                  │  │
│  │   └── outputs/                                                     │  │
│  │                                                                    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## 💰 Cost Comparison: On-Demand vs Spot VM

### Test Configuration

| Parameter | Value |
|-----------|-------|
| Machine Type | e2-standard-2 (2 vCPU, 8 GB RAM) |
| Region | europe-west1-b |
| Disk | 50 GB pd-balanced |
| WRF Case | em_quarter_ss (Idealized Supercell) |
| Simulation Duration | 60 minutes (model time) |

### Results

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PERFORMANCE COMPARISON                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   WRF Execution Time (seconds)                                       │
│                                                                      │
│   On-Demand  ████████████████████████████████████████████████  71s  │
│   Spot VM    █████████████████████████                         38s  │
│                                                                      │
│   0s        20s        40s        60s        80s                    │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Docker Build Time (minutes)                                        │
│                                                                      │
│   On-Demand  ████████████████████████████████████████████  21 min   │
│   Spot VM    ████████████████████████████                  13 min   │
│                                                                      │
│   0min      5min      10min     15min     20min     25min           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Cost Analysis

| Metric | On-Demand | Spot VM | Savings |
|--------|-----------|---------|---------|
| **Hourly Rate** | $0.067/hr | $0.020/hr | 70% |
| **WRF Runtime** | 71 seconds | 38 seconds | 46% faster |
| **Total VM Time** | ~25 min | ~17 min | 32% less |
| **Estimated Cost** | ~$0.028 | ~$0.006 | **79%** |

> **Note:** Spot VMs showed faster execution, likely due to different underlying hardware assignment. Performance may vary between runs.

### Cost Projection for Longer Simulations

| Simulation Length | On-Demand Cost | Spot VM Cost | Monthly Savings (30 runs) |
|-------------------|----------------|--------------|---------------------------|
| 1 hour | $0.067 | $0.020 | $1.41 |
| 6 hours | $0.402 | $0.120 | $8.46 |
| 24 hours | $1.608 | $0.480 | $33.84 |

## Project Structure

```
wrf-gcp-project/
├── main.tf                    # Terraform configuration
├── terraform.tfvars           # Variable values
├── scripts/
│   └── startup.sh             # VM startup automation script
├── README.md                  # This file
└── docs/
    └── WRF_GCP_Report.docx    # Formal project report
```

## Quick Start

### Prerequisites

- Google Cloud SDK (`gcloud`)
- Terraform >= 1.0
- GCP Project with billing enabled

### 1. Clone and Configure

```bash
git clone https://github.com/yourusername/wrf-gcp-project.git
cd wrf-gcp-project

# Authenticate with GCP
gcloud auth application-default login

# Create terraform.tfvars
cat > terraform.tfvars << EOF
project_id      = "your-project-id"
region          = "europe-west1"
wrf_case        = "em_quarter_ss"
wrf_run_minutes = 60
machine_type    = "e2-standard-2"
use_spot        = false
EOF
```

### 2. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 3. Monitor Execution

```bash
# SSH and watch logs
gcloud compute ssh $(terraform output -raw vm_name) \
  --zone $(terraform output -raw vm_zone) \
  -- tail -f /var/log/wrf-startup.log
```

### 4. Access Results

```bash
# List runs
gsutil ls gs://$(terraform output -raw bucket_name)/runs/

# Download specific run
gsutil -m cp -r gs://$(terraform output -raw bucket_name)/runs/TIMESTAMP/ ./local_output/
```

### 5. Cleanup

```bash
terraform destroy
```

## ⚙️ Configuration Options

### Terraform Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `project_id` | (required) | GCP Project ID |
| `region` | `europe-west1` | GCP Region |
| `wrf_case` | `em_quarter_ss` | WRF idealized case name |
| `wrf_run_minutes` | `60` | Simulation duration (model time) |
| `machine_type` | `e2-standard-2` | VM instance type |
| `use_spot` | `false` | Use Spot VM for cost savings |

### Available WRF Cases

| Case | Description | Dimensions |
|------|-------------|------------|
| `em_quarter_ss` | Quarter-circle supercell | 3D |
| `em_b_wave` | Baroclinic wave | 3D |
| `em_squall2d_x` | 2D Squall line | 2D |
| `em_les` | Large Eddy Simulation | 3D |
| `em_hill2d_x` | Flow over hill | 2D |

## 📊 Output Files

| File | Description | Size |
|------|-------------|------|
| `wrfout_d01_*` | Model output (NetCDF) | ~116 MB |
| `wrfinput_d01` | Initial conditions | ~253 MB |
| `namelist.input` | Configuration used | ~5 KB |
| `rsl.out.0000` | Runtime log | ~26 KB |
| `rsl.error.0000` | Error log | ~26 KB |
| `summary.json` | Run metadata | ~300 B |

##  Technical Details

### Docker Image Build

The startup script builds a custom WRF Docker image:

- **Base**: CentOS 7 (with vault mirrors for EOL fix)
- **WRF Version**: 4.0.3
- **Compiler**: GNU (gfortran/gcc)
- **MPI**: OpenMPI
- **NetCDF**: System packages

### Startup Script Flow

```
VM Boot
    │
    ▼
Read GCE Metadata
    │
    ▼
First Boot? ──Yes──> Install Docker, gcloud CLI
    │
    No
    │
    ▼
Docker Image Exists? ──No──> Build WRF Image (~20 min)
    │
    Yes
    │
    ▼
Run ideal.exe (Generate wrfinput_d01)
    │
    ▼
Modify namelist.input (Set run_minutes)
    │
    ▼
Run wrf.exe (Execute simulation)
    │
    ▼
Upload Results to GCS
    │
    ▼
Create summary.json
```

##  Lessons Learned

### 1. WRF is Unforgiving
- Namelist must **exactly match** wrfinput metadata
- One wrong parameter = immediate crash or segfault
- Always validate with `ncdump` before running

### 2. CentOS 7 EOL Issues
- Official mirrors are dead (as of June 2024)
- Solution: Use vault.centos.org mirrors
- Consider migrating to Rocky Linux or AlmaLinux

### 3. Docker Build Caching
- First boot: ~25 minutes (full build)
- Subsequent boots: ~5 minutes (cached image)
- Consider pre-built images for production

### 4. Spot VM Considerations
- **Pros**: 60-70% cost savings
- **Cons**: Can be preempted anytime
- **Best for**: Short, repeatable jobs
- **Avoid for**: Long-running builds

### 5. GCE Metadata is Powerful
- Pass configuration without rebuilding images
- Read with: `curl -H "Metadata-Flavor: Google" http://metadata.google.internal/...`
- Great for Terraform integration

## Future Improvements

- [ ] Pre-built Docker image in Container Registry
- [ ] Real-data simulation (WPS + GFS data)
- [ ] Multi-node MPI parallelization
- [ ] Cloud Build for CI/CD
- [ ] BigQuery for result analysis
- [ ] Visualization pipeline (NCL/Python)

## References

- [WRF Model User Guide](https://www2.mmm.ucar.edu/wrf/users/docs/user_guide_v4/v4.4/contents.html)
- [WRF Idealized Cases](https://www2.mmm.ucar.edu/wrf/OnLineTutorial/Compile/ideal_compile.php)
- [GCP Compute Engine](https://cloud.google.com/compute/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [NCAR WRF Docker](https://github.com/NCAR/WRF_DOCKER)

## License

MIT License - See [LICENSE](LICENSE) for details.

---

**Author:** Tetsurou Kizaki
**Date:** January 2026  
**Course:** Master's Thesis Research — Computer Network Security
