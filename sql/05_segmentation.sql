-- ============================================================================
-- Phase 5: Customer Value & RFM Segmentation
-- Script: sql/05_segmentation.sql
-- Database: MySQL 8.0+
-- Reference Date for recency: 2016-09-30 (end of full active quarter; October only has 2 active dates)
-- Important Note: PERCENT_RANK() is used instead of NTILE() to prevent random tie-breaking.
-- ============================================================================

-- Step 1: Compute percentile ranks and fixed-bucket behavioral scores.
-- Computes balance percentile (excluding NULLs), spend percentile, and RFM scores per customer.
DROP TABLE IF EXISTS customer_segment_prep;
CREATE TABLE customer_segment_prep AS
SELECT 
    customer_id,
    total_spend,
    txn_count,
    days_since_last_txn,
    latest_balance,
    age_group,
    gender,
    location_clean,
    profile_conflict_flag,
    CASE 
        WHEN latest_balance IS NULL THEN NULL
        ELSE PERCENT_RANK() OVER (
            PARTITION BY (CASE WHEN latest_balance IS NOT NULL THEN 1 ELSE 0 END) 
            ORDER BY latest_balance
        )
    END AS balance_pr,
    PERCENT_RANK() OVER (ORDER BY total_spend) AS spend_pr,
    -- Recency score: 0-14 days = 4, 15-29 = 3, 30-44 = 2, 45+ = 1
    CASE 
        WHEN days_since_last_txn <= 14 THEN 4
        WHEN days_since_last_txn <= 29 THEN 3
        WHEN days_since_last_txn <= 44 THEN 2
        ELSE 1
    END AS r_score,
    -- Frequency score: 1 = 1, 2 = 2, 3-4 = 3, 5+ = 4
    CASE 
        WHEN txn_count = 1 THEN 1
        WHEN txn_count = 2 THEN 2
        WHEN txn_count IN (3, 4) THEN 3
        ELSE 4
    END AS f_score,
    -- Monetary score: PERCENT_RANK() on total_spend: >=0.75 = 4, >=0.50 = 3, >=0.25 = 2, else 1
    CASE 
        WHEN PERCENT_RANK() OVER (ORDER BY total_spend) >= 0.75 THEN 4
        WHEN PERCENT_RANK() OVER (ORDER BY total_spend) >= 0.50 THEN 3
        WHEN PERCENT_RANK() OVER (ORDER BY total_spend) >= 0.25 THEN 2
        ELSE 1
    END AS m_score
FROM customer_features;

ALTER TABLE customer_segment_prep ADD PRIMARY KEY (customer_id);

-- Step 2: Create and populate final customer_segments table.
-- Assigns mutually exclusive value and RFM segments using deterministic priority orders.
-- Value Segment rule order:
--   1. 'Premium': balance_pr >= 0.90 OR spend_pr >= 0.90
--   2. 'Unknown balance': latest_balance IS NULL (and not Premium by spend)
--   3. 'High': balance_pr >= 0.70 OR spend_pr >= 0.70
--   4. 'Mid': balance_pr >= 0.30 OR spend_pr >= 0.30
--   5. 'Low': the rest
-- Note on RFM: Dataset spans only 82 days (Aug-Oct 2016), so 'Inactive since August' (R = 1) reflects lack of transactions post-August.
DROP TABLE IF EXISTS customer_segments;
CREATE TABLE customer_segments (
    customer_id             VARCHAR(50) PRIMARY KEY,
    value_segment           VARCHAR(30) NOT NULL,
    rfm_segment             VARCHAR(40) NOT NULL,
    age_group               VARCHAR(20) NOT NULL,
    gender                  VARCHAR(20) NOT NULL,
    location_clean          VARCHAR(50) NOT NULL,
    profile_conflict_flag   TINYINT NOT NULL,
    total_spend             DECIMAL(15,2) NOT NULL,
    latest_balance          DECIMAL(15,2) NULL,
    INDEX idx_val_seg (value_segment),
    INDEX idx_rfm_seg (rfm_segment)
) AS
SELECT 
    customer_id,
    CASE 
        WHEN (balance_pr >= 0.90 OR spend_pr >= 0.90) THEN 'Premium'
        WHEN latest_balance IS NULL THEN 'Unknown balance'
        WHEN (balance_pr >= 0.70 OR spend_pr >= 0.70) THEN 'High'
        WHEN (balance_pr >= 0.30 OR spend_pr >= 0.30) THEN 'Mid'
        ELSE 'Low'
    END AS value_segment,
    CASE 
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions'
        WHEN f_score >= 3 THEN 'Loyal'
        -- Cutoff: p75 total_spend = 1,500.01 (m_score = 4 is top 25% by total spend, txn_count = 1)
        WHEN f_score = 1 AND m_score = 4 THEN 'One-time Higher Spenders'
        WHEN r_score >= 3 AND f_score <= 2 AND m_score <= 3 THEN 'Recent Light'
        -- 'Last seen before mid-Aug (45+ days)': Recency score 1 (days_since_last_txn > 44 as of 2016-09-30, i.e., last txn on or before 2016-08-16).
        -- How it differs from Q4: Q4 counts ALL customers whose last transaction was on or before 2016-08-31 (full August-only cohort with no transaction in September or October).
        -- In contrast, 'Last seen before mid-Aug (45+ days)' is a narrower subset of August-only customers who have been inactive for at least 45 days prior to 2016-09-30.
        WHEN r_score = 1 THEN 'Last seen before mid-Aug (45+ days)'
        ELSE 'Others'
    END AS rfm_segment,
    age_group,
    gender,
    location_clean,
    profile_conflict_flag,
    total_spend,
    latest_balance
FROM customer_segment_prep;

-- Step 3: Clean up intermediate preparation table.
DROP TABLE IF EXISTS customer_segment_prep;

-- ============================================================================
-- Section A: Value Segmentation Analysis (with Medians and Check)
-- ============================================================================

-- Compute median latest balance and aggregate KPIs per value segment
WITH bal_ranked AS (
    SELECT 
        value_segment,
        latest_balance,
        ROW_NUMBER() OVER (PARTITION BY value_segment ORDER BY latest_balance) AS rn,
        COUNT(*) OVER (PARTITION BY value_segment) AS cnt
    FROM customer_segments
    WHERE latest_balance IS NOT NULL
),
segment_medians AS (
    SELECT 
        value_segment,
        ROUND(AVG(latest_balance), 2) AS median_balance
    FROM bal_ranked
    WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
    GROUP BY value_segment
)
SELECT 
    cs.value_segment,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_segments), 2) AS pct_customers,
    ROUND(SUM(cs.total_spend) * 100.0 / (SELECT SUM(total_spend) FROM customer_segments), 2) AS pct_total_spend,
    sm.median_balance,
    ROUND(AVG(cs.total_spend), 2) AS avg_total_spend,
    ROUND(AVG(cf.txn_count), 2) AS avg_txn_count,
    ROUND(AVG(cs.profile_conflict_flag) * 100.0, 2) AS pct_conflict_flag
FROM customer_segments cs
JOIN customer_features cf ON cs.customer_id = cf.customer_id
LEFT JOIN segment_medians sm ON cs.value_segment = sm.value_segment
GROUP BY cs.value_segment, sm.median_balance
ORDER BY 
    CASE cs.value_segment 
        WHEN 'Premium' THEN 1
        WHEN 'High' THEN 2
        WHEN 'Mid' THEN 3
        WHEN 'Low' THEN 4
        WHEN 'Unknown balance' THEN 5
    END;

-- Section A2: Value Segments - Flagged (flag=1) vs Unflagged (flag=0) Breakdown
SELECT 
    value_segment,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN profile_conflict_flag = 1 THEN 1 ELSE 0 END) AS flagged_customers,
    ROUND(SUM(CASE WHEN profile_conflict_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_flagged_customers,
    SUM(CASE WHEN profile_conflict_flag = 0 THEN 1 ELSE 0 END) AS unflagged_customers,
    ROUND(SUM(CASE WHEN profile_conflict_flag = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_unflagged_customers,
    ROUND(SUM(total_spend), 2) AS segment_total_spend,
    ROUND(SUM(CASE WHEN profile_conflict_flag = 1 THEN total_spend ELSE 0 END), 2) AS flagged_spend,
    ROUND(SUM(CASE WHEN profile_conflict_flag = 1 THEN total_spend ELSE 0 END) * 100.0 / SUM(total_spend), 2) AS pct_flagged_spend,
    ROUND(SUM(CASE WHEN profile_conflict_flag = 0 THEN total_spend ELSE 0 END), 2) AS unflagged_spend,
    ROUND(SUM(CASE WHEN profile_conflict_flag = 0 THEN total_spend ELSE 0 END) * 100.0 / SUM(total_spend), 2) AS pct_unflagged_spend
FROM customer_segments
GROUP BY value_segment
ORDER BY 
    CASE value_segment 
        WHEN 'Premium' THEN 1
        WHEN 'High' THEN 2
        WHEN 'Mid' THEN 3
        WHEN 'Low' THEN 4
        WHEN 'Unknown balance' THEN 5
    END;

-- Reconciliation Check: Customer count sum must equal 883,660 and total spend must match customer_features
SELECT 
    (SELECT COUNT(*) FROM customer_segments) AS segments_total_customers,
    (SELECT COUNT(*) FROM customer_features) AS features_total_customers,
    (SELECT ROUND(SUM(total_spend), 2) FROM customer_segments) AS segments_total_spend,
    (SELECT ROUND(SUM(total_spend), 2) FROM customer_features) AS features_total_spend;

SELECT 
    rfm_segment,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_segments), 2) AS pct_customers,
    ROUND(SUM(total_spend) * 100.0 / (SELECT SUM(total_spend) FROM customer_segments), 2) AS pct_total_spend
FROM customer_segments
GROUP BY rfm_segment
ORDER BY 
    CASE rfm_segment 
        WHEN 'Champions' THEN 1
        WHEN 'Loyal' THEN 2
        WHEN 'One-time Higher Spenders' THEN 3
        WHEN 'Recent Light' THEN 4
        WHEN 'Last seen before mid-Aug (45+ days)' THEN 5
        WHEN 'Others' THEN 6
    END;

-- Query RFM Score Spread (R, F, M Distributions)
SELECT 
    'R Score' AS dimension,
    CASE 
        WHEN days_since_last_txn <= 14 THEN '4 (0-14 days)'
        WHEN days_since_last_txn <= 29 THEN '3 (15-29 days)'
        WHEN days_since_last_txn <= 44 THEN '2 (30-44 days)'
        ELSE '1 (45+ days)'
    END AS score_bucket,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features), 2) AS pct_customers
FROM customer_features
GROUP BY score_bucket

UNION ALL

SELECT 
    'F Score' AS dimension,
    CASE 
        WHEN txn_count = 1 THEN '1 (1 txn)'
        WHEN txn_count = 2 THEN '2 (2 txns)'
        WHEN txn_count IN (3, 4) THEN '3 (3-4 txns)'
        ELSE '4 (5+ txns)'
    END AS score_bucket,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features), 2) AS pct_customers
FROM customer_features
GROUP BY score_bucket

UNION ALL

SELECT 
    'M Score' AS dimension,
    score_bucket,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features), 2) AS pct_customers
FROM (
    SELECT 
        CASE 
            WHEN PERCENT_RANK() OVER (ORDER BY total_spend) >= 0.75 THEN '4 (Top 25%)'
            WHEN PERCENT_RANK() OVER (ORDER BY total_spend) >= 0.50 THEN '3 (50-75%)'
            WHEN PERCENT_RANK() OVER (ORDER BY total_spend) >= 0.25 THEN '2 (25-50%)'
            ELSE '1 (Bottom 25%)'
        END AS score_bucket
    FROM customer_features
) m
GROUP BY score_bucket;

SELECT 
    customer_id,
    value_segment,
    rfm_segment,
    age_group,
    gender,
    location_clean,
    profile_conflict_flag,
    total_spend,
    latest_balance
FROM customer_segments
LIMIT 10;

