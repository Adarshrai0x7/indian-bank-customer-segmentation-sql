-- ============================================================================
-- Phase 3: Data Quality & Schema Validation Checks
-- Script: sql/03_validation_checks.sql
-- Database: MySQL 8.0+
-- Purpose: Execute assertions to verify data integrity across modeled tables.
-- All queries are designed to return 0 rows if the dataset is clean and valid.
-- ============================================================================

-- Check 1a: Duplicate primary keys in customers table.
-- Returns 0 rows if customer_id is strictly unique across all customer profiles.
SELECT customer_id, COUNT(*) AS duplicate_count
FROM customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- Check 1b: Duplicate primary keys in transactions table.
-- Returns 0 rows if transaction_id is strictly unique across all fact records.
SELECT transaction_id, COUNT(*) AS duplicate_count
FROM transactions
GROUP BY transaction_id
HAVING COUNT(*) > 1;

-- Check 2: Referential integrity check for orphan transactions.
-- Returns 0 rows if every transaction maps to a valid customer in the customers master dimension.
SELECT t.transaction_id, t.customer_id
FROM transactions t
LEFT JOIN customers c ON t.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- Check 3: Transaction dates outside expected dataset date range (2016-08-01 to 2016-10-21).
-- Returns 0 rows if all transaction dates fall within the verified 82-day operating window.
SELECT transaction_id, transaction_date
FROM transactions
WHERE transaction_date < '2016-08-01' OR transaction_date > '2016-10-21';

-- Check 4: Out-of-range customer ages (< 18 or > 100).
-- Returns 0 rows if all non-null customer ages satisfy the business constraint (18 to 100 years).
SELECT customer_id, age
FROM customers
WHERE age IS NOT NULL AND (age < 18 OR age > 100);

-- Check 5: Row count reconciliation assertion.
-- Returns 0 rows if clean transactions (1,047,732) + excluded zero rows (835) equals staging count (1,048,567).
SELECT 
    clean_count,
    zero_count,
    (clean_count + zero_count) AS total_count,
    staging_count
FROM (
    SELECT 
        (SELECT COUNT(*) FROM transactions) AS clean_count,
        (SELECT COUNT(*) FROM staging_bank_transactions WHERE CAST(TRIM(transaction_amount) AS DECIMAL(15,2)) = 0) AS zero_count,
        (SELECT COUNT(*) FROM staging_bank_transactions) AS staging_count
) counts
WHERE (clean_count + zero_count) != staging_count OR staging_count != 1048567;

-- Check 6: Point-in-time account balance consistency check.
-- Returns 0 rows if each customer's latest_account_balance exactly matches their most recent non-null transaction balance.
WITH latest_txn_balances AS (
    SELECT customer_id, account_balance,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY transaction_date DESC, transaction_id DESC) AS rn
    FROM transactions
    WHERE account_balance IS NOT NULL
)
SELECT 
    c.customer_id,
    c.latest_account_balance,
    ltb.account_balance AS expected_balance
FROM customers c
JOIN latest_txn_balances ltb ON c.customer_id = ltb.customer_id AND ltb.rn = 1
WHERE c.latest_account_balance != ltb.account_balance;

-- Check 6b: Missing balance integrity check.
-- Returns 0 rows if customers with NULL latest_account_balance truly had 0 non-null balances across all transactions.
SELECT c.customer_id
FROM customers c
JOIN transactions t ON c.customer_id = t.customer_id AND t.account_balance IS NOT NULL
WHERE c.latest_account_balance IS NULL;

-- Check 7: Customer age matches date_of_birth as of 2016-10-21.
-- Returns 0 rows if all non-null customer ages exactly equal TIMESTAMPDIFF(YEAR, date_of_birth, '2016-10-21').
SELECT customer_id, date_of_birth, age, TIMESTAMPDIFF(YEAR, date_of_birth, '2016-10-21') AS expected_age
FROM customers
WHERE date_of_birth IS NOT NULL 
  AND age != TIMESTAMPDIFF(YEAR, date_of_birth, '2016-10-21');

-- Check 8: Customer gender integrity check.
-- Returns 0 rows if all customer gender values strictly equal 'M', 'F', or 'Unknown'.
SELECT customer_id, gender
FROM customers
WHERE gender NOT IN ('M', 'F', 'Unknown') OR gender IS NULL;
