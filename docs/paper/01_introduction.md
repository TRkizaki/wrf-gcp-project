# 1. Introduction

## 1.1 Motivation

Small-scale atmospheric modeling — a graduate student running a localized WRF case on a laptop, a lecturer demonstrating WRF in a classroom, a researcher prototyping a new physics scheme — sits awkwardly in the HPC ecosystem. Production weather centers have dedicated clusters; the rest of the community improvises with shared HPC time, university servers, or local workstations. **The result: bespoke setups, undocumented dependencies, weeks of compile-time debugging, and no good story for reproducibility.**

> TODO: 1-2 paragraphs about your specific motivation (Ohrid precipitation interest, master's program context, prior failures with bespoke setups).

## 1.2 Why Cloud, and Why GCP

> TODO. Key arguments to make:
> - On-demand compute eliminates queue waits.
> - Per-second billing makes small experiments financially trivial.
> - Standardized images and containers eliminate "works on my machine".
> - GCP specifically: chosen for free-trial credits, simple Terraform provider, Spot VM pricing.

## 1.3 Problem Statement

How do we deploy WRF on commodity cloud infrastructure such that:

1. The full deployment is reproducible from a single source-controlled config?
2. The cost-performance tradeoffs are quantified for the small-scale regime (single-VM, < 1 hour)?
3. The workflow survives common cloud disruptions (Spot preemption, free-tier budget limits)?

## 1.4 Contributions

This paper contributes:

1. **A complete Terraform-driven pipeline** for WRF on GCP, including VPC, IAM, GCS, and Compute Engine provisioning, plus a metadata-driven startup script that compiles WRF inside a CentOS-7 container, runs the simulation, and uploads outputs to GCS.

2. **An empirical 2x2 cost-performance matrix** for the `em_quarter_ss` idealized supercell case across machine size (e2-standard-2 vs e2-standard-4) and provisioning model (Spot vs on-demand).

3. **A characterization of Spot VM behavior under preemption** for HPC-style workloads, including the observation that persistent-disk Docker image caching enables sub-90-second recovery.

4. **A fully reproducible artifact** — every result regeneratable from a single `terraform apply` against the provided `main.tf` and configuration variables.

## 1.5 Roadmap

Section 2 surveys related work in cloud HPC, IaC for science, and containerized weather modeling. Section 3 details our methodology — IaC design, container build, automation flow. Section 4 describes the experimental matrix and variance characterization. Section 5 presents results. Section 6 discusses implications and threats to validity. Section 7 concludes with future work.
