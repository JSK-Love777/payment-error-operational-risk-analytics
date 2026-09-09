# Data setup

Raw source files are intentionally **not committed** to this portfolio repository.

## Source

**Financial Transactions Dataset: Analytics** by ComputingVictor on Kaggle  
https://www.kaggle.com/datasets/computingvictor/transactions-fraud-datasets

## Files required for reproduction

Download the dataset and use the following source files:

- `transactions_data.csv`
- `users_data.csv`
- `cards_data.csv`

The supplied master SQL expects these three MySQL tables to exist before the analytical script is run:

- `raw_transactions`
- `raw_users`
- `raw_cards`

## Reproduction sequence

1. Download the three source CSV files from Kaggle.
2. Create and populate `raw_transactions`, `raw_users`, and `raw_cards` in MySQL 8+.
3. Run `sql/Payment_Error_Operational_Risk_Analytics.sql` from top to bottom.
4. Open `excel/Payment_Error_Operational_Risk_Analytics.xlsx` to review independent Q1-Q5 cross-validation.
5. Open `powerbi/Payment_Error_Operational_Risk_Analytics.pbix` in Power BI Desktop for the interactive report.

> Local `LOAD DATA` paths are environment-specific and are therefore not hard-coded into the portfolio master SQL.

## Why raw data is excluded

The repository keeps the public portfolio lightweight and avoids redistributing a large third-party dataset. Reproducibility is provided through the public source, required filenames, expected raw-table names, analysis script, and validation workbook.
