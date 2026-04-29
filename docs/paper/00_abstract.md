# Abstract

> **TODO — write this last, after results are final.** Target: 150 words. Should hit:
> 1. The problem (small-scale WRF deployments are bespoke and hard to reproduce)
> 2. The approach (Terraform + container + GCS-backed automation, single `terraform apply`)
> 3. The experiment (2x2 matrix on GCP: machine size x provisioning model)
> 4. The three headline findings (vCPU helps build not workload; spot economics flip under preemption; persistent-disk Docker cache enables fast spot recovery)
> 5. The cost (full reproduction in $0.16, ~75 min wallclock)

## Draft seed (rewrite for final)

We present an Infrastructure-as-Code (IaC) approach to deploying the Weather Research and Forecasting (WRF) model on Google Cloud Platform for small-scale atmospheric modeling experiments. The complete pipeline — from VPC and IAM provisioning through containerized WRF execution and result archival — is encoded in a single Terraform configuration reproducible via `terraform apply`. Using the idealized supercell case (`em_quarter_ss`), we measure cost and wallclock across a 2x2 experimental matrix varying machine size (e2-standard-2 vs e2-standard-4) and provisioning model (Spot vs on-demand). We report three findings: (1) additional vCPUs accelerate the WRF source compile by ~23% but provide no benefit to the serial `wrf.exe` workload itself; (2) Spot VM economics flip negative under preemption, with one preemption observed in three Spot trials; and (3) persistent-disk Docker image caching enables Spot recovery in under 90 seconds, a methodologically important pattern for cost-aware cloud HPC.
