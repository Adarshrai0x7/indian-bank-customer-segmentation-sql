# Indian Bank Customer Segmentation using SQL (MySQL)

## 1. Objective
This project analyzes about 1 million bank transactions from an Indian retail bank from August to October 2016. The goal is to clean messy transaction records, create summary tables per customer, and segment customers by account balance and spending patterns. The analysis is done in SQL (MySQL) to answer business questions about customer demographics, peak transaction times, and spending tiers.

---

## 2. Dataset
- **Source**: Kaggle dataset [Bank Customer Segmentation by Shivam Bansal](https://www.kaggle.com/datasets/shivamb/bank-customer-segmentation).
- **Size**: 1,048,567 rows spanning August 1, 2016 to October 21, 2016.
- **Raw Columns**:
  - `TransactionID`: Unique ID for each transaction.
  - `CustomerID`: Customer identifier.
  - `CustomerDOB`: Date of birth as text. Contains 2-digit years, blanks, and dummy `1/1/1800`.
  - `CustGender`: Gender marked as 'M', 'F', 'T', or blank.
  - `CustLocation`: Customer location text or address line.
  - `CustAccountBalance`: Account balance at the time of transaction.
  - `TransactionDate`: Date in DD/MM/YY format.
  - `TransactionTime`: Time stored as an integer (e.g. 143000 for 14:30:00).
  - `TransactionAmount (INR)`: Transaction amount in Indian Rupees.

---

## 3. Tools and SQL Features Used
- **Database**: MySQL 8.0+
- **Language**: SQL (MySQL 8.0+)
- **SQL Features**:
  - Common Table Expressions (CTE) and Recursive CTE (`WITH`, `WITH RECURSIVE`)
  - Window functions (`PERCENT_RANK()`, `ROW_NUMBER()`, `DENSE_RANK()`, `SUM() OVER ()`, `AVG() OVER ()`)
  - Date and time functions (`STR_TO_DATE()`, `TIME()`, `HOUR()`, `DAYNAME()`, `DATE_FORMAT()`, `TIMESTAMPDIFF()`, `DATEDIFF()`)
  - String functions (`TRIM()`, `LPAD()`, `UPPER()`, `SUBSTRING_INDEX()`)
  - Conditional logic (`CASE WHEN ... THEN ... END`)
  - Table joins (`INNER JOIN`, `LEFT JOIN`, `CROSS JOIN`, `UNION ALL`)
  - Indexes on primary keys, dates, customer IDs, and location columns.

---

## 4. Folder Structure
```text
bank-segmentation-sql/
├── .gitignore                       # Ignores large raw data CSV and local environment
├── README.md                        # Project documentation, findings, and running guide
├── data/
│   ├── README.md                    # Data source link and download steps
│   └── bank_transactions.csv        # Raw dataset (downloaded from Kaggle; gitignored)
├── sql/
│   ├── 01_create_staging.sql        # Creates staging table and loads raw CSV
│   ├── 02_clean_and_model.sql       # Cleans data and creates customers and transactions tables
│   ├── 03_validation_checks.sql     # Data checks (all must return 0 rows)
│   ├── 04_customer_features.sql     # Aggregates metrics per customer
│   ├── 05_segmentation.sql          # Assigns Value and RFM segments
│   └── 06_business_questions.sql    # Answers business questions Q1 to Q11 and supplementary queries
├── results/                         # Exported query CSV results
└── docs/
    ├── cleaning_log.md              # Detailed step-by-step cleaning audit log
    └── data_dictionary.md           # Column definitions for all database tables
```

---

## 5. How to Run

Execute the SQL scripts in this exact order using MySQL Workbench or the `mysql` CLI:

1. `sql/01_create_staging.sql`: Creates `staging_bank_transactions` and loads the raw CSV data.
2. `sql/02_clean_and_model.sql`: Cleans text fields, standardizes locations and dates, builds indexes, and creates `customers` and `transactions` tables.
3. `sql/03_validation_checks.sql`: Runs quality checks. Every test must return 0 rows.
4. `sql/04_customer_features.sql`: Builds `customer_features` with lifetime spend and recency.
5. `sql/05_segmentation.sql`: Assigns `value_segment` and `rfm_segment` in `customer_segments`.
6. `sql/06_business_questions.sql`: Runs all business queries Q1 to Q11 and supplementary checks.

The full run takes about 30 to 40 minutes (depends on your computer). `02_clean_and_model.sql` and `06_business_questions.sql` are the longest. Result CSV files were exported from the query results.

### How I Checked the Numbers
Key results were re-checked in MySQL Workbench against the raw tables: customer counts, Q1, Q3, Q7 hours and weekdays, Q8, Q11 totals.

### Running via MySQL CLI
From the project root directory, run with `--local-infile=1`:
```bash
mysql --local-infile=1 -u root -p bank_segmentation < sql/01_create_staging.sql
mysql -u root -p bank_segmentation < sql/02_clean_and_model.sql
mysql -u root -p bank_segmentation < sql/03_validation_checks.sql
mysql -u root -p bank_segmentation < sql/04_customer_features.sql
mysql -u root -p bank_segmentation < sql/05_segmentation.sql
mysql -u root -p bank_segmentation < sql/06_business_questions.sql
```

### Running via MySQL Workbench
1. Open and execute each script in order (`01` through `06`).
2. In `01_create_staging.sql`, specify the full absolute path to `bank_transactions.csv` if the relative path returns Error 2 (e.g. `C:/path/to/data/bank_transactions.csv`).

### Troubleshooting and Settings
- **Error 1046 No database selected**: run `USE bank_segmentation;` first, or double-click the database in Workbench.
- **`LOAD DATA LOCAL INFILE` Setup**:
  1. In MySQL server, ensure local infile is enabled:
     ```sql
     SET GLOBAL local_infile = 1;
     ```
  2. In MySQL Workbench: Edit Connection -> Advanced -> Others -> add `OPT_LOCAL_INFILE=1`.
- **Workbench Query Timeout**:
  Because `02_clean_and_model.sql` and `05_segmentation.sql` process ~1 million rows:
  - In MySQL Workbench: `Edit` -> `Preferences` -> `SQL Editor` -> set **DBMS connection read timeout** to `600` (or `1200`) seconds.


---

## 6. Data Cleaning Summary
Full details and query outputs are in [docs/cleaning_log.md](docs/cleaning_log.md).

| Metric / Step | Count | Note |
| --- | --- | --- |
| Raw records | 1,048,567 | Total rows in raw CSV file. |
| Excluded transactions | 835 | Rows where amount = 0 (no negative amounts exist). Reason is not given in the dataset. |
| Clean transactions | 1,047,732 | Saved in `transactions` table. |
| Blank balances | 2,364 | Converted empty balance text to `NULL` (in clean transactions; 2,369 in raw staging). |
| Unique customer IDs | 883,660 | Saved in `customers` table (884,265 in raw data; 605 had only zero-amount rows). |
| Single-transaction customers | 740,240 | 83.77% of customers appear only once. |
| Repeat customers | 143,420 | 16.23% of customers have 2 or more transactions. |
| Conflicting birth dates | 128,005 | Repeat customers with 2 or more different valid birth dates. |
| Conflicting genders | 59,820 | Repeat customers with both 'M' and 'F' recorded. |
| Profile conflict flag = 1 | 132,754 | Total customers marked with profile conflict flag (15.02%). |

---

## 7. How Segments Are Built

### Value Segments
Account balance and total spend are heavily skewed. Static rupee cutoffs do not fit the distribution well. Percentile ranks (`PERCENT_RANK()`) are used instead:
- `balance_pr`: Percentile rank of `latest_balance` calculated over non-null balances (`PARTITION BY (CASE WHEN latest_balance IS NOT NULL THEN 1 ELSE 0 END) ORDER BY latest_balance`). Evaluates to `NULL` if `latest_balance IS NULL`.
- `spend_pr`: Percentile rank of `total_spend` calculated across all customers (`ORDER BY total_spend`).

Value segments are assigned using the exact `CASE` statement in `sql/05_segmentation.sql`:
```sql
CASE 
    WHEN (balance_pr >= 0.90 OR spend_pr >= 0.90) THEN 'Premium'
    WHEN latest_balance IS NULL THEN 'Unknown balance'
    WHEN (balance_pr >= 0.70 OR spend_pr >= 0.70) THEN 'High'
    WHEN (balance_pr >= 0.30 OR spend_pr >= 0.30) THEN 'Mid'
    ELSE 'Low'
END AS value_segment
```
- **Premium**: `balance_pr >= 0.90 OR spend_pr >= 0.90` (Top 10% balance or top 10% spend).
- **Unknown balance**: `latest_balance IS NULL` (and not Premium by spend; exactly 1,515 customers).
- **High**: `balance_pr >= 0.70 OR spend_pr >= 0.70` (70th percentile or above in balance or spend, and not Premium).
- **Mid**: `balance_pr >= 0.30 OR spend_pr >= 0.30` (30th percentile or above in balance or spend, and not Premium or High).
- **Low**: Remaining customers (`ELSE 'Low'`).

### RFM Scores
Age is calculated as of 2016-10-21 (the last date in the data). Recency is measured from 2016-09-30 because October has only 2 active dates.
Scores are assigned in `customer_segment_prep` using fixed buckets:
- **Recency (`r_score`)**:
  - `4`: `days_since_last_txn <= 14` (0 to 14 days)
  - `3`: `days_since_last_txn <= 29` (15 to 29 days)
  - `2`: `days_since_last_txn <= 44` (30 to 44 days)
  - `1`: `ELSE 1` (45+ days, i.e. last transaction on or before 2016-08-16)
- **Frequency (`f_score`)**:
  - `4`: `txn_count >= 5` (5+ transactions)
  - `3`: `txn_count IN (3, 4)` (3 to 4 transactions)
  - `2`: `txn_count = 2` (2 transactions)
  - `1`: `txn_count = 1` (1 transaction)
- **Monetary (`m_score`)**:
  - `4`: `PERCENT_RANK() OVER (ORDER BY total_spend) >= 0.75` (Top 25% spend, cutoff: ₹1,500.01)
  - `3`: `PERCENT_RANK() OVER (ORDER BY total_spend) >= 0.50` (50th-75th percentile spend, cutoff: ₹541.00)
  - `2`: `PERCENT_RANK() OVER (ORDER BY total_spend) >= 0.25` (25th-50th percentile spend, cutoff: ₹200.00)
  - `1`: `ELSE 1` (Bottom 25% spend, spend < ₹200.00)

### RFM Segments Assignment Order
Segments are assigned in `sql/05_segmentation.sql` using a deterministic, mutually exclusive `CASE` order:
```sql
CASE 
    WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions'
    WHEN f_score >= 3 THEN 'Loyal'
    WHEN f_score = 1 AND m_score = 4 THEN 'One-time Higher Spenders'
    WHEN r_score >= 3 AND f_score <= 2 AND m_score <= 3 THEN 'Recent Light'
    WHEN r_score = 1 THEN 'Last seen before mid-Aug (45+ days)'
    ELSE 'Others'
END AS rfm_segment
```
1. **Champions**: `r_score >= 3 AND f_score >= 3 AND m_score >= 3` (Active in last 30 days, 3+ transactions, top 50% spend).
2. **Loyal**: `f_score >= 3` (3+ transactions; catches repeat customers who do not meet the Champions recency/monetary bar).
3. **One-time Higher Spenders**: `f_score = 1 AND m_score = 4` (Single transaction with spend in top 25%, cutoff: total spend >= ₹1,500.01).
4. **Recent Light**: `r_score >= 3 AND f_score <= 2 AND m_score <= 3` (Active in last 30 days, 1-2 transactions, bottom 75% spend).
5. **Last seen before mid-Aug (45+ days)**: `r_score = 1` (Inactive for 45+ days as of 2016-09-30; last transaction on or before 2016-08-16).
   *Note*: This differs from Q4 (August-only cohort). Q4 counts all customers whose last transaction was on or before 2016-08-31 with no transactions in September or October. In contrast, 'Last seen before mid-Aug (45+ days)' is a narrower subset inactive for at least 45 days prior to 2016-09-30.
6. **Others**: Remaining customers who do not match earlier criteria.

*Note on CASE order*: 272,419 customers have `r_score = 1`, but only 217,201 land in 'Last seen before mid-Aug (45+ days)' because 55,218 fall into 'One-time Higher Spenders' (`f_score = 1 AND m_score = 4`) or 'Loyal' first.

---

## 8. Key Findings

Every number below comes directly from exported CSV files in `results/`.

1. **Spend Concentration (Q1)**:
   The top 10% of customers (88,381 customers, spending ₹3,580.00 or more) account for 63.26% of all spending (₹1,044,242,228.45). The top 1% (8,837 customers, spending ₹23,535.27 or more) account for 26.83% of all spending (₹442,888,052.63). Among single-transaction customers, the top 10% drives 64.69% of spend.
2. **Age Distribution (Q2)**:
   Customers aged 26-35 make up 47.28% of the base (417,785 customers), with an average transaction of ₹1,401.83 and median balance of ₹17,283.99. Customers aged 18-25 make up 27.31% (241,320 customers) with median balance ₹9,203.26. Customers aged 46-60 and 60+ make up small shares (5.00% and 1.39%) but hold higher median balances (₹45,651.21 and ₹53,099.19). Exactly 5.05% of customers (44,587) have an unknown age.
3. **Top Locations (Q3)**:
   Delhi NCR is the largest named location with 250,377 customers (297,098 transactions, 28.36% of all transactions) and ₹478,196,599.07 total value (28.97% of total value). Mumbai Metro is second with 136,749 customers (162,139 transactions, 15.48%) and ₹263,582,043.67 total value. Bangalore is third with 77,336 customers (91,686 transactions, 8.75%) and ₹136,982,412.24 total value. Raw location text that could not be mapped (OTHER) accounts for 24.76% of transactions (259,453) and 24.69% of spend (₹407,575,699.27). International locations make up 0.13% of transactions (1,327).
4. **Gender Split (Q5)**:
   Gender analysis uses the customers table and excludes 804 Unknown records (0.09%). Men make up 73.20% of customers (646,880) and women make up 26.70% (235,976). Women have a higher average transaction amount (₹1,649.36 vs ₹1,548.32, which is ₹101.04 higher) and a 32.5% higher median balance (₹20,583.51 vs ₹15,533.18, which is ₹5,050.33 higher).
5. **Monthly Volume and Incomplete Dates (Q6)**:
   August 2016 had 31 active dates with 653,376 transactions (avg 21,076.65 per active date). September had 22 active dates (8 missing calendar dates) with 390,701 transactions (avg 17,759.14 per active date, down 15.7%). October had only 2 active dates (16 and 21 Oct) with 3,655 transactions.
6. **Busiest Hours and Days (Q7)**:
   Peak hours by transaction count are 20:00 (97,036 txns, ₹147,145,920.45) and 19:00 (94,379 txns, ₹148,838,517.02). By total value, 19:00 is higher than 20:00 although 20:00 has more transactions. In August, weekends averaged about 24,000 transactions per date (Saturday: 24,057.00; Sunday: 24,211.25) compared to about 20,000 on weekdays (Monday: 20,203.80; Tuesday: 19,582.20; Wednesday: 20,203.40; Thursday: 20,109.25; Friday: 19,979.75).
7. **High Balance, Low Activity Customers (Q8)**:
   47,208 unflagged single-transaction customers (5.34% of all customers) have balances in the top 30% (>= ₹43,414.61) but spend in the bottom 30% (<= ₹248.00). Together they hold ₹12,987,912,788.80 (₹1,298.79 Crore) in account balances recorded at the last transaction. Their median balance is ₹102,543.08 and average balance is ₹275,121.01 (the average balance is much higher than the median because a few large balances pull it up), while their average spend is only ₹121.83.
8. **Value Segments vs Spend Share (Q10)**:
   Premium customers make up 17.95% of customer count (158,602) but generate 67.90% of total spend. Low value customers make up 12.31% of customer count (108,737) and generate 0.66% of spend. In RFM, One-time Higher Spenders drive 55.51% of total spend (151,516 customers, ₹916,340,807.09 spend).
9. **Robustness Comparison (All vs Single-Transaction Baseline)**:
   Comparing All Customers to Single-Transaction baseline shows:
   - Average transaction amount differs by up to 17.76% (18-25 M: ₹946.49 vs ₹803.76).
   - Median balance differs by only 0.00% to 2.90% (18-25 M differs by 1.90%, 60+ F differs by 2.90%, 36-45 F differs by 0.00%).
   - Median spend differs by 21.65% to 36.36% for ages 18-35 (18-25 M: ₹300 vs ₹220; 18-25 F: ₹397 vs ₹300; 26-35 M: ₹500 vs ₹400; 26-35 F: ₹680 vs ₹559) because `total_spend` adds all repeat transactions together.
10. **Profile Conflicts and Spend Share**:
    132,754 customers have profile conflict flags (15.02% of all customers), accounting for ₹430,901,391.03 (26.10% of total spend). In the Champions segment, 13,301 out of 13,385 customers (99.37%) are flagged. In the Loyal segment, 5,199 out of 5,232 customers (99.37%) are flagged.

---

## 9. Recommendations (Ideas for Testing)
*Note: These are business ideas based on data patterns, not proven results.*

1. **Deposit Cross-Sell**: Contact the 47,208 high-balance, low-spend customers who hold ₹1,298.79 Crore in account balances recorded at the last transaction. Offer term deposits, wealth management, or auto-debit savings plans.
2. **Campaign Timing**: Schedule promotions and app push notifications between 19:00 and 21:00, when most transactions happen.
3. **Identity Resolution Fix**: Before launching loyalty reward programs, clean up source customer IDs. Because 99.37% of Champions and Loyal customers show conflicting dates of birth or genders, loyalty rewards may go to shared IDs rather than individual customers.

---

## 10. Limitations
- **Short time period**: The dataset covers only 82 calendar days with 55 active dates.
- **Missing calendar dates**: 27 calendar dates have zero records. September has 8 missing dates, and October has only 2 active dates (16 and 21 Oct).
- **October incomplete**: October data cannot be used to measure monthly trends.
- **August concentration**: August holds 62.36% of all transactions. Customers with no transactions after August are not churned; they simply appeared once in a single sample window.
- **CustomerID quality**: 143,420 repeat customer IDs exist, but 128,005 have 2 or more different valid birth dates and 59,820 have conflicting genders (both M and F recorded). 132,754 customers are flagged.
- **Champions and Loyal flagged**: 99.37% of customers in Champions and Loyal segments have profile conflicts. They may be shared IDs rather than single loyal customers. The cause is not verified.
- **Messy location text**: 24.76% of transactions (259,453) fall into OTHER because raw text contains branch codes, state names, or abbreviations that cannot be mapped to a specific city.
- **Zero-amount records**: 835 transactions had amount = 0 (no negative amounts exist in the raw data) with no explanation.
- **Missing banking fields**: The data has no information on account type (savings vs current), loans, credit cards, or transaction channel (ATM vs POS vs online).
- **Kolkata account pattern**: Customers C1525358, C6825363, and C7525325 show repeated ₹100,000 transactions, DOB 1800, and ending balance ₹157,333.33 in Kolkata. This is a suspicious pattern, but the cause is not verified.
- **Older data**: Transactions are from 2016 and do not reflect current digital payment habits in India (such as UPI).

---

## 11. What I Would Do Next
- Build an interactive Power BI dashboard to let branch managers filter customer segments by city and age.
- Test deduplication logic using phone numbers or account numbers if more raw fields become available.
- Collect at least 12 months of daily transaction data to track retention and seasonal trends.
