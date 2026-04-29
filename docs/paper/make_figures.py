#!/usr/bin/env python3
"""Generate paper figures from results/experiments.csv.

Outputs three PNGs into figures/:
  fig1_cost_per_run.png         — bar chart of cost per run, preemption highlighted
  fig2_wallclock_breakdown.png  — stacked bar of t_setup/t_build/t_run/t_upload per run
  fig3_build_vs_vcpu.png        — t_build_s vs vCPU count, on-demand only

Usage:
  python make_figures.py
  # requires: pandas, matplotlib
"""

from pathlib import Path
import pandas as pd
import matplotlib.pyplot as plt

CSV_PATH = Path(__file__).parent.parent.parent / "results" / "experiments.csv"
OUT_DIR = Path(__file__).parent / "figures"
OUT_DIR.mkdir(exist_ok=True)


def load() -> pd.DataFrame:
    df = pd.read_csv(CSV_PATH)
    df["short_id"] = df["run_id"].apply(lambda s: s.split("T")[0][-2:] + "-" + s.split("-")[1][:5])
    return df


def fig1_cost_per_run(df: pd.DataFrame) -> None:
    fig, ax = plt.subplots(figsize=(8, 4))
    colors = ["#d62728" if "PREEMPTION" in str(s) else "#1f77b4" for s in df["status"]]
    ax.bar(df["short_id"], df["cost_est_usd"], color=colors)
    ax.set_ylabel("Cost (USD)")
    ax.set_xlabel("Run")
    ax.set_title("Cost per run — preempted runs highlighted in red")
    ax.set_xticklabels(df["short_id"], rotation=30, ha="right")
    plt.tight_layout()
    plt.savefig(OUT_DIR / "fig1_cost_per_run.png", dpi=150)
    plt.close()


def fig2_wallclock_breakdown(df: pd.DataFrame) -> None:
    sub = df.dropna(subset=["t_setup_s", "t_build_s", "t_run_s", "t_upload_s"]).copy()
    fig, ax = plt.subplots(figsize=(8, 4))
    bottoms = [0] * len(sub)
    for col, label, color in [
        ("t_setup_s", "setup", "#cccccc"),
        ("t_build_s", "build", "#1f77b4"),
        ("t_run_s", "run", "#2ca02c"),
        ("t_upload_s", "upload", "#ff7f0e"),
    ]:
        ax.bar(sub["short_id"], sub[col], bottom=bottoms, label=label, color=color)
        bottoms = [b + v for b, v in zip(bottoms, sub[col])]
    ax.set_ylabel("Wallclock (s)")
    ax.set_xlabel("Run")
    ax.set_title("Wallclock breakdown by phase")
    ax.legend()
    ax.set_xticklabels(sub["short_id"], rotation=30, ha="right")
    plt.tight_layout()
    plt.savefig(OUT_DIR / "fig2_wallclock_breakdown.png", dpi=150)
    plt.close()


def fig3_build_vs_vcpu(df: pd.DataFrame) -> None:
    on_demand = df[(df["spot"] == False) & (df["t_build_s"].notna())]
    if on_demand.empty:
        print("WARNING: no on-demand runs with t_build_s; fig3 skipped")
        return
    grouped = on_demand.groupby("vcpu")["t_build_s"].mean().reset_index()
    fig, ax = plt.subplots(figsize=(6, 4))
    ax.bar(grouped["vcpu"].astype(str) + " vCPU", grouped["t_build_s"], color="#1f77b4")
    ax.set_ylabel("t_build (s)")
    ax.set_xlabel("Machine size (on-demand only)")
    ax.set_title("WRF source build time vs vCPU count")
    for i, v in enumerate(grouped["t_build_s"]):
        ax.text(i, v + 20, f"{int(v)} s", ha="center")
    plt.tight_layout()
    plt.savefig(OUT_DIR / "fig3_build_vs_vcpu.png", dpi=150)
    plt.close()


def main() -> None:
    df = load()
    print(f"Loaded {len(df)} rows from {CSV_PATH}")
    fig1_cost_per_run(df)
    fig2_wallclock_breakdown(df)
    fig3_build_vs_vcpu(df)
    print(f"Wrote figures to {OUT_DIR}/")


if __name__ == "__main__":
    main()
