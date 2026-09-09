# Methodology & Metric Dictionary

## Core grains

| Stage | Grain | Purpose |
|---|---|---|
| Q1 Customer | Customer | Entity-level behavior |
| Q1 Card | Card | Detect localized card behavior |
| Q2 | Payment Method | Compare volume and error propensity |
| Q3 | MCC × Hour × Payment Method | Reliable high-error operating segments |
| Q4 lower grain | MCC × Hour × Payment Method × Card | Explain repetition inside Q3 segments |
| Q5 | Q3 segment | Compare Ordinary High-Error vs Outlier severity |

## Baseline error rate

`error transactions / total transactions` = approximately **1.59%**.

## Q3 minimum segment size

The minimum eligible segment size is **601 transactions**, derived at a 95% confidence level with a ±1.0 percentage-point margin of error using the baseline error rate. Its purpose is to reduce unstable low-volume rate spikes before high-error classification.

## Q3 thresholds

- High-error threshold: **2.1109%**
- Outlier threshold: **3.6282%**
- Outlier rule: `Q3 + 1.5 × IQR` on eligible segment error rates
- MCC recurrence rule: same MCC contains at least **2** high-error operating conditions

## Q4 repetition metric

**Avg Errors / Error Card** = error transactions within a segment ÷ distinct error-generating cards within that segment.

The displayed overall **2.21** is an **unweighted average of the 391 segment-level values**, not a pooled global card ratio.

Descriptive repetition categories:

- Low-repeat: `< 1.5`
- Mixed: `1.5 to < 2.0`
- Repeat-concentrated: `≥ 2.0`

These are analyst-defined descriptive routing categories, not universal statistical thresholds.

## Q4 breadth and concentration

- **Repeat-Error Card Share**: share of error-generating cards that repeat errors
- **Top-Card Error Share**: share of segment errors attributable to the dominant error-generating card

## Q5 population logic

Ordinary High-Error and Outlier are **mutually exclusive** populations. The 349 Ordinary High-Error segments exclude the 42 Outliers.

Q4/Q5 structural comparisons use **unweighted segment-level averages** unless explicitly labeled otherwise. The flagged error rate shown in the overview is transaction-weighted.
