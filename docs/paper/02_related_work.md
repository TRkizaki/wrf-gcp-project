# 2. Related Work

> TODO: For each bucket below, find 2-4 strong citations and write 1-2 sentences each. Recommend Google Scholar searches with the key phrases noted.

## 2.1 Cloud HPC for Weather and Climate

> Search: "WRF cloud computing", "AWS HPC weather", "NOAA cloud initiative".

Key prior work to acknowledge:
- **NOAA's cloud strategy** (Big Data Project, partnership with AWS/Azure/GCP) — moves operational data to cloud but uses dedicated HPC clusters.
- **AWS ParallelCluster + WRF** — community blog posts and AWS reference architectures; mostly large-scale (multi-node MPI), not small-scale single-VM.
- **Microsoft CycleCloud + Azure HPC** — similar large-scale focus.

**Gap:** prior cloud-WRF work focuses on production-scale multi-node deployments. Small-scale single-VM deployments (this work's regime) are under-documented.

## 2.2 Infrastructure-as-Code for Scientific Computing

> Search: "Terraform scientific computing", "reproducible cloud research", "IaC reproducibility".

Key concepts:
- **Reproducibility crisis in computational science** (e.g., Donoho's reproducibility framework).
- **IaC adoption in research** — sparse literature; mostly software-engineering perspectives applied to bioinformatics or ML pipelines.

**Gap:** IaC is well-studied for web infrastructure but rarely framed as a contribution to *scientific reproducibility*. This paper frames Terraform-as-methodology.

## 2.3 Containerized Weather and Climate Models

> Search: "WRF Docker", "WRF Singularity", "containerized weather model".

Key prior work:
- **NCAR's `wrf-docker`** repository — official container.
- **University of Manchester `wrf-wps` image** (`ghcr.io/uomresearchit/wrf-wps`) — used in earlier iterations of this work.
- **WRF in Singularity** — common in shared-HPC settings.

**This work's choice:** build WRF from source inside a CentOS-7 container at deploy time. Tradeoff: ~20-min cold build vs guaranteed identical configuration. Discussion in Section 3.3.

## 2.4 Spot/Preemptible VM Resilience

> Search: "spot instance fault tolerance", "preemptible VM checkpoint", "spot HPC workflow".

Key prior work:
- **Checkpoint-restart systems** (DMTCP, BLCR) for traditional HPC — heavyweight for short cloud jobs.
- **Spot-aware schedulers** (e.g., AWS Spot Fleet, GCP managed instance groups with auto-restart).
- **Cost-vs-reliability studies** of spot/preemptible instances for ML training and batch workloads.

**This work's contribution to this thread:** for short atmospheric modeling jobs (< 30 min wallclock post-build), the persistent boot disk *is* the checkpoint — Docker image cache survives preemption, enabling restart-and-resume in under 90 seconds without explicit checkpointing logic.
