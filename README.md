# Indian Bank Customer Segmentation using SQL

An end-to-end SQL analytics project analyzing ~1,000,000 customer transactions from an Indian retail bank (August to October 2016). Built entirely in **MySQL 8.0** using pure SQL queries, strict data quality assertions, customer segmentation modeling, and business question analytics.

---

## 1. Project Overview

- **Dataset**: ~1M anonymized transaction records (~67.5 MB raw CSV).
- **Core Database**: MySQL 8.0+ Community Server.
- **Tools**: SQL (DDL, DML, CTEs, Window Functions, Dimensional Modeling), Python (`mysql-connector-python`, `python-dotenv` for pipeline orchestration).
- **Domain**: Retail Banking Analytics & Customer Relationship Management (ICICI Bank portfolio case study).

---

## 2. Repository Structure

```text
bank-segmentation-sql/
├── .env.example             # Template for local MySQL connection credentials
├── .gitignore               # Ignores raw data CSV and local environment files
├── run_pipeline.py          # Command-line runner to execute and audit all phases
├── data/
│   └── README.md            # Kaggle data source link and placement instructions
├── sql/
│   ├── 01_create_staging.sql        # Staging DDL and LOAD DATA LOCAL INFILE command
│   ├── 02_clean_and_model.sql       # Data cleaning and modeled tables (customers, transactions)
│   ├── 03_validation_checks.sql     # Data quality assertions (0 rows expected)
│   ├── 04_customer_features.sql     # Customer feature engineering (recency ref: 2016-09-30)
│   ├── 05_segmentation.sql          # Value segments (Percentile ranks) & RFM (fixed buckets)
│   └── 06_business_questions.sql    # 12 business questions & actionable KPI answers
├── results/                 # Exported query CSV files for full auditability
└── docs/
    └── cleaning_log.md      # Audited transformation log with exact row counts & queries
```

---

## 3. Database Architecture & Modeled Tables

The raw staging table (`staging_bank_transactions`: 1,048,567 rows) is cleaned and normalized into two relational tables:

1. **`transactions` (Fact Table - 1,047,732 rows)**:
   - `transaction_id` (Primary Key)
   - `customer_id` (Indexed foreign key)
   - `transaction_date` (DATE, indexed)
   - `transaction_time` (TIME), `transaction_hour` (0–23)
   - `day_of_week` (Monday–Sunday), `month_label` ('2016-08', '2016-09', '2016-10')
   - `amount` (DECIMAL(15,2), strictly > 0)
   - `account_balance` (DECIMAL(15,2), NULL if blank)

2. **`customers` (Dimension Table - 883,660 rows)**:
   - `customer_id` (Primary Key)
   - `gender` ('M', 'F', 'Unknown')
   - `date_of_birth` (DATE, NULL if placeholder/invalid)
   - `age` (Computed as of reference date `2016-10-21`)
   - `age_group` ('18-25', '26-35', '36-45', '46-60', '60+', 'Unknown')
   - `location_clean` (Standardized into 30+ metro clusters or 'OTHER')
   - `latest_account_balance` (Balance from the customer's most recent transaction)
   - `profile_conflict_flag` (1 if customer had contradictory DOB/gender/location, else 0)

---

## 4. Key Data Limitations

### A. Calendar Coverage & Recency Limitation
- **August**: 31 active dates (653,376 transactions). Full month.
- **September**: 22 active dates (390,701 transactions). 8 calendar dates have no recorded transactions.
- **October**: Only 2 active dates (16 and 21 Oct, total 3,655 transactions). 19 dates missing.
- **Limitation**: Oct has only 2 days of data and Sep is missing 8 days, so recency and monthly trends are limited.
- **Adjustment**: Because October data is incomplete, recency is anchored to `2016-09-30`. Customers with an October transaction get `days_since_last_txn = 0` using `GREATEST(0, DATEDIFF('2016-09-30', last_txn_date))`. Monthly transaction trends compare volume per active date, and October is marked as partial data.

### B. The CustomerID Profile Conflict Problem
- **Clean Customers**: 883,660 total.
- **Single-transaction customers**: 740,240 (83.8%) — demographics are 100% consistent.
- **Repeat transactors (2+ transactions)**: 143,420 customers.
- **Evidence of Conflict**: 128,005 of repeat transactors have 2+ different valid dates of birth, 59,820 have transactions recorded under both Male and Female, and 132,754 customers have at least one profile conflict (`profile_conflict_flag = 1`).
- **Cause**: Cause not verified. Possible reasons (guesses only):
  1. Joint or family accounts shared by multiple household members.
  2. Synthetic ID generation hashed account numbers rather than individual citizen IDs.
  3. Terminal-level data entry typos at POS swipe points.
- **Handling in Analysis**:
  - Value segmentation (Balance + Spend) serves as the primary segmentation model because account balances and spend represent actual financial liquidity regardless of user profile noise.
  - Demographic breakdowns are analyzed on all customers AND checked side-by-side on single-transaction customers (where data is unconflicted).
  - RFM segmentation is a secondary view using fixed buckets.

---

## 5. How to Run the Pipeline

1. **Clone the repository and set up environment**:
   ```bash
   cp bank-segmentation-sql/.env.example bank-segmentation-sql/.env
   # Edit .env with your MySQL host, port, user, and password
   ```

2. **Download Data**:
   - Download `bank_transactions.csv` from [Kaggle](https://www.kaggle.com/datasets/shivamb/bank-customer-segmentation) and place it in `bank-segmentation-sql/data/`.

3. **Execute Pipeline**:
   ```bash
   cd bank-segmentation-sql

   # Run all phases sequentially:
   python run_pipeline.py all

   # Or run specific phases:
   python run_pipeline.py phase1    # Setup & bulk load staging
   python run_pipeline.py phase2    # Data cleaning & modeled tables
   python run_pipeline.py phase3    # Data quality assertions (0 rows expected)
   python run_pipeline.py phase4    # Customer feature store
   python run_pipeline.py phase5    # Value & RFM customer segmentation
   python run_pipeline.py phase6    # Business questions & findings
   ```
