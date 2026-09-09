# Validation Strategy

The project uses three layers of validation.

## 1. SQL QA

The master SQL includes checks for:

- expected table grain
- row-count and reconciliation consistency
- threshold and classification logic
- mutually exclusive severity populations
- repeated-MCC recurrence logic

## 2. Excel cross-validation

`Payment_Error_Operational_Risk_Analytics.xlsx` contains **16 worksheets** spanning Q1-Q5. Lower-grain SQL exports are used to independently reconstruct important metrics with Excel formulas rather than simply restating final SQL outputs.

Validation examples include:

- Q1 customer/card aggregation checks
- Q2 payment-method rate reconstruction
- Q3 minimum-n, eligible error rates, quartiles/IQR, high-error and outlier classification
- Q4 card repetition metrics and segment-level classifications
- Q5 Ordinary High-Error vs Outlier structural comparison

## 3. Power BI semantic QA

The report is checked against the validated SQL/Excel definitions to ensure:

- measures preserve the intended numerator and denominator
- filter context does not change the analytical grain
- severity populations remain mutually exclusive
- weighted and unweighted metrics retain their intended meaning
- page terminology is consistent with the SQL and Excel definitions

## Validation principle

The workbook is an independent cross-check layer. It is not the primary analytical engine and is not intended to replace the SQL pipeline.
