# Project Narrative

## Objective

This project asks where payment errors become operationally meaningful, whether those errors are broadly distributed or repeatedly concentrated on the same cards, and how investigation priority should change when severity and concentration overlap.

The analysis follows one investigation chain:

**Behavior → Payment Method → Reliable Segment Screening → Card-Level Structure → Investigation Priority**

## Q1 — Customer vs Card Granularity

Customer-level aggregation can hide localized behavior when one customer owns multiple cards. The analysis therefore compares customer and card behavior before choosing the entity level for deeper investigation. Card-level IQR-only anomaly share is materially higher than customer-level share, supporting card-level follow-up while retaining customer context.

## Q2 — Payment Method Behavior

Transaction volume alone does not determine operational priority. Online represents only **11.71%** of transactions but records the highest aggregate error rate at **2.28%**, versus approximately **1.49%** for Swipe and **1.51%** for Chip. Payment method is retained as a diagnostic dimension, not treated as evidence of causation.

## Q3 — Reliable High-Error Segment Screening

The segment grain is **MCC × hour of day × payment method**. A raw high error rate is not sufficient: segments first require **n ≥ 601**, derived from a 95% confidence level with a ±1.0 percentage-point margin around the baseline error rate. Eligible segments are then classified using distribution-based thresholds.

Final screening results:

- High-error threshold: **2.1109%**
- Outlier threshold: **3.6282%**
- High-error-flagged segments: **391**
- Ordinary High-Error: **349**
- Outliers: **42**

Recurrence is evaluated at the MCC level to identify merchant categories that repeatedly appear under different operating conditions.

## Q4 — Card Repetition & Concentration

Q4 keeps all 391 Q3 high-error segments and temporarily lowers the grain to card level inside each segment. The 601-transaction rule remains a Q3 operating-segment eligibility rule; it is not reapplied to individual cards.

The project distinguishes three descriptive repetition structures:

- Low-repeat: **225 segments (57.54%)**, avg errors/error card **1.28**
- Mixed: **66 (16.88%)**, avg **1.67**
- Repeat-concentrated: **100 (25.58%)**, avg **4.67**

The purpose is investigation routing: dispersed structures suggest shared operating conditions first, while repeat-concentrated structures support repeated-card and dominant-card review.

## Q5 — Outlier Severity & Targeting

Q5 compares mutually exclusive Ordinary High-Error and Outlier populations. Outliers are not only higher-rate segments; their card-level structure shifts strongly toward repeat concentration.

- Repeat-concentrated share: **21.78% → 57.14%**
- Repeat-concentrated avg errors/error card: **3.97 → 6.88**
- Repeat-error card share: **50.27% → 50.75%**
- Top-card error share: **21.27% → 35.41%**

This supports a final prioritization rule: rank **Outlier + Repeat-concentrated** operating segments by top-card concentration, then trace dominant card IDs within those segments.

## Final analytical distinction

- **Q4 = Investigation Routing:** how should a flagged segment be investigated?
- **Q5 = Investigation Priority:** among flagged segments, where should investigation start?

The project is descriptive and diagnostic. It does not claim fraud detection, causality, or loss reduction.
