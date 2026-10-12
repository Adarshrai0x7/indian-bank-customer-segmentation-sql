-- ============================================================================
-- Phase 4: Customer Feature Engineering
-- Script: sql/04_customer_features.sql
-- Database: MySQL 8.0+
-- Reference Date for recency: 2016-09-30 (end of full active quarter; October only has 2 active dates)
-- Customers with an October transaction get days_since_last_txn = 0 using GREATEST(0, DATEDIFF(...)).
-- ============================================================================

-- Step 1: Create customer feature table consolidating behavioral, recency, and profile attributes.
-- Aggregates transactions per customer and joins clean master customer demographics.
DROP TABLE IF EXISTS customer_features;
CREATE TABLE customer_features (
    customer_id             VARCHAR(50) PRIMARY KEY,
    total_spend             DECIMAL(15,2) NOT NULL,
    txn_count               INT NOT NULL,
    avg_txn_amount          DECIMAL(15,2) NOT NULL,
    max_txn_amount          DECIMAL(15,2) NOT NULL,
    first_txn_date          DATE NOT NULL,
    last_txn_date           DATE NOT NULL,
    days_since_last_txn     INT NOT NULL,
    active_days             INT NOT NULL,
    avg_balance             DECIMAL(15,2) NULL,
    latest_balance          DECIMAL(15,2) NULL,
    age                     INT NULL,
    age_group               VARCHAR(20) NOT NULL,
    gender                  VARCHAR(20) NOT NULL,
    location_clean          VARCHAR(50) NOT NULL,
    profile_conflict_flag   TINYINT NOT NULL,
    INDEX idx_cf_spend (total_spend),
    INDEX idx_cf_recency (days_since_last_txn),
    INDEX idx_cf_flag (profile_conflict_flag),
    INDEX idx_cf_location (location_clean)
);

-- Step 2: Populate customer features by aggregating fact transactions and joining customers dimension.
-- Computes lifetime spend, transaction volume, recency relative to 2016-09-30, and average liquidity.
INSERT INTO customer_features (
    customer_id,
    total_spend,
    txn_count,
    avg_txn_amount,
    max_txn_amount,
    first_txn_date,
    last_txn_date,
    days_since_last_txn,
    active_days,
    avg_balance,
    latest_balance,
    age,
    age_group,
    gender,
    location_clean,
    profile_conflict_flag
)
SELECT 
    t.customer_id,
    ROUND(SUM(t.amount), 2) AS total_spend,
    COUNT(*) AS txn_count,
    ROUND(AVG(t.amount), 2) AS avg_txn_amount,
    MAX(t.amount) AS max_txn_amount,
    MIN(t.transaction_date) AS first_txn_date,
    MAX(t.transaction_date) AS last_txn_date,
    GREATEST(0, DATEDIFF('2016-09-30', MAX(t.transaction_date))) AS days_since_last_txn,
    COUNT(DISTINCT t.transaction_date) AS active_days,
    ROUND(AVG(t.account_balance), 2) AS avg_balance,
    c.latest_account_balance AS latest_balance,
    c.age,
    c.age_group,
    c.gender,
    c.location_clean,
    c.profile_conflict_flag
FROM transactions t
JOIN customers c ON t.customer_id = c.customer_id
GROUP BY 
    t.customer_id,
    c.latest_account_balance,
    c.age,
    c.age_group,
    c.gender,
    c.location_clean,
    c.profile_conflict_flag;

-- Step 3: Create customer_features_view as a convenient SQL view abstraction.
-- Provides easy query access to the customer feature store for downstream segmentation models.
CREATE OR REPLACE VIEW customer_features_view AS
SELECT * FROM customer_features;

-- ============================================================================
-- Verification Queries
-- ============================================================================

-- Query 1: Total Spend distribution summary across all customers
SELECT 
    MIN(total_spend) AS min_spend,
    MAX(total_spend) AS max_spend,
    ROUND(AVG(total_spend), 2) AS avg_spend,
    ROUND(SUM(total_spend), 2) AS total_market_spend,
    COUNT(*) AS total_customers
FROM customer_features;

-- Query 2: Top 5 customers ranked by total spend with transaction count and conflict flag
SELECT 
    customer_id,
    total_spend,
    txn_count,
    profile_conflict_flag,
    avg_txn_amount,
    max_txn_amount,
    latest_balance
FROM customer_features
ORDER BY total_spend DESC
LIMIT 5;

-- Query 3: Hand verification check for 3 sample customers (Single Txn, Repeat Conflict, NULL Balance)
SELECT 
    customer_id,
    total_spend,
    txn_count,
    avg_txn_amount,
    max_txn_amount,
    first_txn_date,
    last_txn_date,
    days_since_last_txn,
    active_days,
    avg_balance,
    latest_balance,
    age,
    age_group,
    gender,
    location_clean,
    profile_conflict_flag
FROM customer_features
WHERE customer_id IN ('C1010012', 'C1010011', 'C1011425')
ORDER BY customer_id;
