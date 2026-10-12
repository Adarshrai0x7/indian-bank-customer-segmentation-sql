# Data Dictionary

This document describes all tables and columns created in the project.

---

## 1. Table: `customers`

Clean master dimension table. It stores one row per customer ID.

| Column | Type | Meaning | How Derived |
| --- | --- | --- | --- |
| `customer_id` | VARCHAR(50) | Unique customer ID | Copied from `staging_bank_transactions` (primary key). |
| `gender` | VARCHAR(20) | Customer gender ('M', 'F', 'Unknown') | Mode gender across transactions. Ties are broken by the latest transaction date. |
| `date_of_birth` | DATE | Customer birth date | Mode date of birth across transactions. Placeholder dates (`1/1/1800`) and ages outside 18-100 are set to NULL. |
| `age` | INT | Customer age in years | Calculated using `TIMESTAMPDIFF(YEAR, date_of_birth, '2016-10-21')` with reference date 2016-10-21. |
| `age_group` | VARCHAR(20) | Age bucket | Grouped into '18-25', '26-35', '36-45', '46-60', '60+', and 'Unknown' (for NULL dates). |
| `location_clean` | VARCHAR(50) | Cleaned city or region | Mode location matched against 30+ major metro areas, 'INTERNATIONAL', or 'OTHER'. |
| `latest_account_balance` | DECIMAL(15,2) | Most recent balance in INR | Taken from the latest transaction where balance was not null. |
| `txn_count` | INT | Total transactions for this customer | Count of transactions in the dataset (`COUNT(*)`). |
| `profile_conflict_flag` | TINYINT | Flag for conflicting profile data | Set to 1 if the customer has 2 or more distinct valid birth dates, or both 'M' and 'F' recorded; 0 otherwise. |

---

## 2. Table: `transactions`

Clean transaction fact table. It stores all valid transactions with amount greater than zero.

| Column | Type | Meaning | How Derived |
| --- | --- | --- | --- |
| `transaction_id` | VARCHAR(50) | Unique transaction ID | Copied from `staging_bank_transactions` (primary key). |
| `customer_id` | VARCHAR(50) | Customer ID who made the transaction | Foreign key linked to `customers(customer_id)`. |
| `transaction_date` | DATE | Date of transaction | Parsed from raw text using `STR_TO_DATE(TRIM(transaction_date), '%d/%m/%y')`. |
| `transaction_time` | TIME | Time of transaction | Parsed from raw text padded to 6 digits using `TIME(STR_TO_DATE(LPAD(..., 6, '0'), '%H%i%s'))`. |
| `transaction_hour` | TINYINT | Hour of transaction (0-23) | Extracted from `transaction_time` using `HOUR()`. |
| `day_of_week` | VARCHAR(20) | Name of weekday | Extracted from `transaction_date` using `DAYNAME()`. |
| `month_label` | VARCHAR(10) | Month label (YYYY-MM) | Extracted from `transaction_date` using `DATE_FORMAT(..., '%Y-%m')`. |
| `amount` | DECIMAL(15,2) | Transaction amount in INR | Converted from text using `CAST()`. Rows with amount <= 0 were excluded. |
| `account_balance` | DECIMAL(15,2) | Account balance at transaction in INR | Converted from text using `CAST()`. Blank values were converted to NULL. |

---

## 3. Table: `customer_features`

Aggregated behavioral feature table. It summarizes activity per customer ID.

| Column | Type | Meaning | How Derived |
| --- | --- | --- | --- |
| `customer_id` | VARCHAR(50) | Unique customer ID | Primary key. |
| `total_spend` | DECIMAL(15,2) | Total money spent in INR | `SUM(amount)` from `transactions`. |
| `txn_count` | INT | Total number of transactions | `COUNT(*)` from `transactions`. |
| `avg_txn_amount` | DECIMAL(15,2) | Average spend per transaction in INR | `AVG(amount)` from `transactions`. |
| `max_txn_amount` | DECIMAL(15,2) | Largest single transaction in INR | `MAX(amount)` from `transactions`. |
| `first_txn_date` | DATE | First transaction date | `MIN(transaction_date)` from `transactions`. |
| `last_txn_date` | DATE | Last transaction date | `MAX(transaction_date)` from `transactions`. |
| `days_since_last_txn` | INT | Days since last transaction | `GREATEST(0, DATEDIFF('2016-09-30', last_txn_date))` relative to 2016-09-30. |
| `active_days` | INT | Number of distinct active days | `COUNT(DISTINCT transaction_date)` from `transactions`. |
| `avg_balance` | DECIMAL(15,2) | Average account balance in INR | `AVG(account_balance)` from `transactions`. |
| `latest_balance` | DECIMAL(15,2) | Latest known account balance in INR | Joined from `customers.latest_account_balance`. |
| `age` | INT | Customer age | Joined from `customers.age`. |
| `age_group` | VARCHAR(20) | Age bucket | Joined from `customers.age_group`. |
| `gender` | VARCHAR(20) | Customer gender | Joined from `customers.gender`. |
| `location_clean` | VARCHAR(50) | Customer cleaned location | Joined from `customers.location_clean`. |
| `profile_conflict_flag` | TINYINT | Conflict flag | Joined from `customers.profile_conflict_flag`. |

---

## 4. Table: `customer_segments`

Customer segmentation table combining value percentiles and RFM scores.

| Column | Type | Meaning | How Derived |
| --- | --- | --- | --- |
| `customer_id` | VARCHAR(50) | Unique customer ID | Primary key. |
| `gender` | VARCHAR(20) | Customer gender | Copied from `customer_features`. |
| `age` | INT | Customer age | Copied from `customer_features`. |
| `age_group` | VARCHAR(20) | Age bucket | Copied from `customer_features`. |
| `location_clean` | VARCHAR(50) | Cleaned city or region | Copied from `customer_features`. |
| `total_spend` | DECIMAL(15,2) | Lifetime spend in INR | Copied from `customer_features`. |
| `txn_count` | INT | Total transactions | Copied from `customer_features`. |
| `avg_txn_amount` | DECIMAL(15,2) | Average spend per transaction in INR | Copied from `customer_features`. |
| `latest_balance` | DECIMAL(15,2) | Latest balance in INR | Copied from `customer_features`. |
| `days_since_last_txn` | INT | Days since last transaction | Copied from `customer_features`. |
| `profile_conflict_flag` | TINYINT | Profile conflict flag | Copied from `customer_features`. |
| `balance_percentile` | DECIMAL(7,4) | Percentile rank of latest balance | `PERCENT_RANK() OVER (ORDER BY latest_balance)` among non-null balances. NULL if balance is missing. |
| `spend_percentile` | DECIMAL(7,4) | Percentile rank of total spend | `PERCENT_RANK() OVER (ORDER BY total_spend)` across all customers. |
| `value_segment` | VARCHAR(30) | Value tier | Assigned by percentiles: Premium (balance_pr >= 0.90 or spend_pr >= 0.90), High (balance_pr >= 0.70 or spend_pr >= 0.70), Mid (balance_pr >= 0.30 or spend_pr >= 0.30), Low (remainder), Unknown balance (latest_balance IS NULL and not Premium). |
| `r_score` | TINYINT | Recency score (1-4) | 4 if days <= 14; 3 if days <= 29; 2 if days <= 44; 1 if days >= 45 (measured from 2016-09-30). |
| `f_score` | TINYINT | Frequency score (1-4) | 4 if txn_count >= 5; 3 if txn_count in (3, 4); 2 if txn_count = 2; 1 if txn_count = 1. |
| `m_score` | TINYINT | Monetary score (1-4) | 4 if spend_pr >= 0.75 (spend >= 1,500.01); 3 if spend_pr >= 0.50 (spend >= 541.00); 2 if spend_pr >= 0.25 (spend >= 200.00); 1 if spend_pr < 0.25. |
| `rfm_segment` | VARCHAR(40) | Behavioral RFM segment | Assigned using a CASE statement in order: Champions, Loyal, One-time Higher Spenders, Recent Light, Last seen before mid-Aug (45+ days), and Others. |
