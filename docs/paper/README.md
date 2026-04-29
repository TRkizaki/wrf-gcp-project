# Master's Thesis Paper — WRF on GCP

Working title: **Reproducible Cloud WRF: An Infrastructure-as-Code Approach to Cost-Aware Small-Scale Atmospheric Modeling on GCP**

## Structure

| File | Purpose | Status |
|---|---|---|
| `00_abstract.md` | 150-word abstract — write last | TODO |
| `01_introduction.md` | Context, problem, contributions | outline |
| `02_related_work.md` | Cloud HPC, IaC, container WRF, spot studies | outline |
| `03_methodology.md` | IaC pipeline, container, automation flow | outline + facts |
| `04_experiments.md` | Matrix design, variance design, limitations | outline + facts |
| `05_results.md` | Three findings, figures, dataset table | outline + data |
| `06_discussion.md` | Implications, threats to validity | outline |
| `07_conclusion.md` | Summary + future work | outline |
| `08_reproducibility.md` | Exact commands + git refs | outline + commands |

## Source data

All quantitative claims trace back to `../../results/experiments.csv`. Six rows:
- **Rows 1-4:** primary 2x2 matrix (machine_type x spot/on-demand)
- **Row 5:** variance replicate 1/3 of std-2-spot baseline
- (n=2/3 and 3/3 not collected — free-trial budget constraint, see 06_discussion.md)

## Building figures

```bash
cd docs/paper
python make_figures.py
# outputs: figures/fig1_cost_per_run.png
#          figures/fig2_wallclock_breakdown.png
#          figures/fig3_build_vs_vcpu.png
```

## Source-of-truth git references

- **Instrumentation commit:** `e580b2d`
- **Matrix complete:** `620e9c6`
- **Variance rep 1/3:** `39c255c`

Each commit on `feat/experiment-instrumentation` corresponds to one or more dataset rows. Reviewers can checkout any commit and reproduce the state.

## Conversion to LaTeX / Word

```bash
# all sections to a single PDF via pandoc
pandoc 0[0-8]_*.md -o thesis.pdf --pdf-engine=xelatex
# or to docx for advisor markup
pandoc 0[0-8]_*.md -o thesis.docx
```
