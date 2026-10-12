-- ============================================================================
-- Phase 6: Business Questions & Actionable Insights
-- Script: sql/06_business_questions.sql
-- Database: MySQL 8.0+
-- Reference Date for recency: 2016-09-30 (October has only 2 active dates)
-- ============================================================================

-- Check: Identify dates between 2016-08-01 and 2016-10-21 with no transactions recorded.
-- Uses a recursive CTE to generate the calendar range and checks against distinct active dates.
WITH RECURSIVE all_dates AS (
    SELECT DATE('2016-08-01') AS calendar_date
    UNION ALL
    SELECT DATE_ADD(calendar_date, INTERVAL 1 DAY)
    FROM all_dates
    WHERE calendar_date < '2016-10-21'
)
SELECT 
    ad.calendar_date,
    DAYNAME(ad.calendar_date) AS day_of_week
FROM all_dates ad
LEFT JOIN (
    SELECT DISTINCT transaction_date 
    FROM transactions
) t ON ad.calendar_date = t.transaction_date
WHERE t.transaction_date IS NULL
ORDER BY ad.calendar_date;

-- Q1: Top 1%, 10%, and 20% share of total spend with cutoff amounts.
-- Evaluated for both 'All Customers' and clean baseline 'Txn Count = 1'.
-- Uses PERCENT_RANK() on total_spend to establish exact threshold cutoffs.
WITH ranked_all AS (
    SELECT 
        total_spend,
        PERCENT_RANK() OVER (ORDER BY total_spend DESC) AS spend_pct_rank
    FROM customer_features
),
cutoffs_all AS (
    SELECT 
        (SELECT MIN(total_spend) FROM ranked_all WHERE spend_pct_rank <= 0.01) AS cutoff_top1,
        (SELECT MIN(total_spend) FROM ranked_all WHERE spend_pct_rank <= 0.10) AS cutoff_top10,
        (SELECT MIN(total_spend) FROM ranked_all WHERE spend_pct_rank <= 0.20) AS cutoff_top20,
        (SELECT SUM(total_spend) FROM ranked_all) AS total_cohort_spend
    FROM ranked_all
    LIMIT 1
),
ranked_single AS (
    SELECT 
        total_spend,
        PERCENT_RANK() OVER (ORDER BY total_spend DESC) AS spend_pct_rank
    FROM customer_features
    WHERE txn_count = 1
),
cutoffs_single AS (
    SELECT 
        (SELECT MIN(total_spend) FROM ranked_single WHERE spend_pct_rank <= 0.01) AS cutoff_top1,
        (SELECT MIN(total_spend) FROM ranked_single WHERE spend_pct_rank <= 0.10) AS cutoff_top10,
        (SELECT MIN(total_spend) FROM ranked_single WHERE spend_pct_rank <= 0.20) AS cutoff_top20,
        (SELECT SUM(total_spend) FROM ranked_single) AS total_cohort_spend
    FROM ranked_single
    LIMIT 1
)
SELECT 
    'All Customers' AS cohort,
    tier,
    cutoff_amount,
    customers,
    tier_spend,
    ROUND(tier_spend * 100.0 / total_cohort_spend, 2) AS pct_total_spend
FROM (
    SELECT 
        'Top 1%' AS tier,
        c.cutoff_top1 AS cutoff_amount,
        COUNT(*) AS customers,
        ROUND(SUM(r.total_spend), 2) AS tier_spend,
        c.total_cohort_spend
    FROM ranked_all r, cutoffs_all c
    WHERE r.total_spend >= c.cutoff_top1
    GROUP BY c.cutoff_top1, c.total_cohort_spend
    UNION ALL
    SELECT 
        'Top 10%' AS tier,
        c.cutoff_top10 AS cutoff_amount,
        COUNT(*) AS customers,
        ROUND(SUM(r.total_spend), 2) AS tier_spend,
        c.total_cohort_spend
    FROM ranked_all r, cutoffs_all c
    WHERE r.total_spend >= c.cutoff_top10
    GROUP BY c.cutoff_top10, c.total_cohort_spend
    UNION ALL
    SELECT 
        'Top 20%' AS tier,
        c.cutoff_top20 AS cutoff_amount,
        COUNT(*) AS customers,
        ROUND(SUM(r.total_spend), 2) AS tier_spend,
        c.total_cohort_spend
    FROM ranked_all r, cutoffs_all c
    WHERE r.total_spend >= c.cutoff_top20
    GROUP BY c.cutoff_top20, c.total_cohort_spend
) t_all

UNION ALL

SELECT 
    'Txn Count = 1' AS cohort,
    tier,
    cutoff_amount,
    customers,
    tier_spend,
    ROUND(tier_spend * 100.0 / total_cohort_spend, 2) AS pct_total_spend
FROM (
    SELECT 
        'Top 1%' AS tier,
        c.cutoff_top1 AS cutoff_amount,
        COUNT(*) AS customers,
        ROUND(SUM(r.total_spend), 2) AS tier_spend,
        c.total_cohort_spend
    FROM ranked_single r, cutoffs_single c
    WHERE r.total_spend >= c.cutoff_top1
    GROUP BY c.cutoff_top1, c.total_cohort_spend
    UNION ALL
    SELECT 
        'Top 10%' AS tier,
        c.cutoff_top10 AS cutoff_amount,
        COUNT(*) AS customers,
        ROUND(SUM(r.total_spend), 2) AS tier_spend,
        c.total_cohort_spend
    FROM ranked_single r, cutoffs_single c
    WHERE r.total_spend >= c.cutoff_top10
    GROUP BY c.cutoff_top10, c.total_cohort_spend
    UNION ALL
    SELECT 
        'Top 20%' AS tier,
        c.cutoff_top20 AS cutoff_amount,
        COUNT(*) AS customers,
        ROUND(SUM(r.total_spend), 2) AS tier_spend,
        c.total_cohort_spend
    FROM ranked_single r, cutoffs_single c
    WHERE r.total_spend >= c.cutoff_top20
    GROUP BY c.cutoff_top20, c.total_cohort_spend
) t_single;

-- Q2: Age group breakdown: Customer count, % share, average amount per transaction, and median balance.
-- Evaluated for both 'All Customers' and 'Txn Count = 1', including 60+ and Unknown age cohorts.
WITH bal_ranked_all AS (
    SELECT 
        age_group,
        latest_balance,
        ROW_NUMBER() OVER (PARTITION BY age_group ORDER BY latest_balance) AS rn,
        COUNT(*) OVER (PARTITION BY age_group) AS cnt
    FROM customer_features
    WHERE latest_balance IS NOT NULL
),
age_medians_all AS (
    SELECT 
        age_group,
        ROUND(AVG(latest_balance), 2) AS median_balance
    FROM bal_ranked_all
    WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
    GROUP BY age_group
),
bal_ranked_single AS (
    SELECT 
        age_group,
        latest_balance,
        ROW_NUMBER() OVER (PARTITION BY age_group ORDER BY latest_balance) AS rn,
        COUNT(*) OVER (PARTITION BY age_group) AS cnt
    FROM customer_features
    WHERE txn_count = 1 AND latest_balance IS NOT NULL
),
age_medians_single AS (
    SELECT 
        age_group,
        ROUND(AVG(latest_balance), 2) AS median_balance
    FROM bal_ranked_single
    WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
    GROUP BY age_group
)
SELECT 
    'All Customers' AS cohort,
    cf.age_group,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features), 2) AS pct_customers,
    ROUND(SUM(cf.total_spend) / SUM(cf.txn_count), 2) AS avg_amount_per_txn,
    am.median_balance
FROM customer_features cf
LEFT JOIN age_medians_all am ON cf.age_group = am.age_group
GROUP BY cf.age_group, am.median_balance

UNION ALL

SELECT 
    'Txn Count = 1' AS cohort,
    cf.age_group,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features WHERE txn_count = 1), 2) AS pct_customers,
    ROUND(SUM(cf.total_spend) / SUM(cf.txn_count), 2) AS avg_amount_per_txn,
    ams.median_balance
FROM customer_features cf
LEFT JOIN age_medians_single ams ON cf.age_group = ams.age_group
WHERE cf.txn_count = 1
GROUP BY cf.age_group, ams.median_balance

ORDER BY 
    cohort,
    CASE age_group 
        WHEN '18-25' THEN 1
        WHEN '26-35' THEN 2
        WHEN '36-45' THEN 3
        WHEN '46-60' THEN 4
        WHEN '60+' THEN 5
        WHEN 'Unknown' THEN 6
    END;

-- Q3: Top 10 named locations (excluding OTHER) by customer count, transactions, and total value.
-- "customers per location" uses each customer's resolved location from the customers table, and "transactions and value" come from customer_features (txn_count and total_spend summed by location_clean), so both use the same location.
-- Part A: Top 10 by Transaction Count
WITH totals AS (
    SELECT SUM(txn_count) AS grand_txns, SUM(total_spend) AS grand_spend 
    FROM customer_features
)
SELECT 
    'By Txn Count' AS ranking_metric,
    cf.location_clean,
    COUNT(*) AS customer_count,
    SUM(cf.txn_count) AS txn_count,
    ROUND(SUM(cf.txn_count) * 100.0 / t.grand_txns, 2) AS pct_total_txns,
    ROUND(SUM(cf.total_spend), 2) AS total_value,
    ROUND(SUM(cf.total_spend) * 100.0 / t.grand_spend, 2) AS pct_total_value
FROM customer_features cf
CROSS JOIN totals t
WHERE cf.location_clean NOT IN ('OTHER')
GROUP BY cf.location_clean, t.grand_txns, t.grand_spend
ORDER BY txn_count DESC
LIMIT 10;

-- Part B: Top 10 by Total Value
WITH totals AS (
    SELECT SUM(txn_count) AS grand_txns, SUM(total_spend) AS grand_spend 
    FROM customer_features
)
SELECT 
    'By Value' AS ranking_metric,
    cf.location_clean,
    COUNT(*) AS customer_count,
    SUM(cf.txn_count) AS txn_count,
    ROUND(SUM(cf.txn_count) * 100.0 / t.grand_txns, 2) AS pct_total_txns,
    ROUND(SUM(cf.total_spend), 2) AS total_value,
    ROUND(SUM(cf.total_spend) * 100.0 / t.grand_spend, 2) AS pct_total_value
FROM customer_features cf
CROSS JOIN totals t
WHERE cf.location_clean NOT IN ('OTHER')
GROUP BY cf.location_clean, t.grand_txns, t.grand_spend
ORDER BY total_value DESC
LIMIT 10;

-- Q4: Customers with no transaction in September or October (August only).
-- Finding Note: This is NOT customer churn. August holds 62.36% of all transactions (653,376 / 1,047,732)
-- in the entire dataset, and 83.77% of all customers only transact once. 89.66% of August-only customers appear
-- exactly once. Their absence post-August reflects data sampling concentration, not customer defection.
SELECT 
    COUNT(*) AS august_only_customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features), 2) AS pct_customers,
    SUM(CASE WHEN txn_count = 1 THEN 1 ELSE 0 END) AS single_txn_august_customers,
    ROUND(SUM(CASE WHEN txn_count = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_single_txn,
    ROUND(SUM(latest_balance), 2) AS total_latest_balance,
    ROUND(AVG(latest_balance), 2) AS avg_latest_balance
FROM customer_features
WHERE last_txn_date <= '2016-08-31';

-- Q5: Gender split: Customer count, % share, average amount per transaction, and median balance.
-- Evaluated for both 'All Customers' and 'Txn Count = 1', including Unknown gender.
WITH bal_ranked_gender AS (
    SELECT 
        gender,
        latest_balance,
        ROW_NUMBER() OVER (PARTITION BY gender ORDER BY latest_balance) AS rn,
        COUNT(*) OVER (PARTITION BY gender) AS cnt
    FROM customer_features
    WHERE latest_balance IS NOT NULL
),
gender_medians_all AS (
    SELECT 
        gender,
        ROUND(AVG(latest_balance), 2) AS median_balance
    FROM bal_ranked_gender
    WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
    GROUP BY gender
),
bal_ranked_gender_single AS (
    SELECT 
        gender,
        latest_balance,
        ROW_NUMBER() OVER (PARTITION BY gender ORDER BY latest_balance) AS rn,
        COUNT(*) OVER (PARTITION BY gender) AS cnt
    FROM customer_features
    WHERE txn_count = 1 AND latest_balance IS NOT NULL
),
gender_medians_single AS (
    SELECT 
        gender,
        ROUND(AVG(latest_balance), 2) AS median_balance
    FROM bal_ranked_gender_single
    WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
    GROUP BY gender
)
SELECT 
    'All Customers' AS cohort,
    cf.gender,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features), 2) AS pct_customers,
    ROUND(SUM(cf.total_spend) / SUM(cf.txn_count), 2) AS avg_amount_per_txn,
    gm.median_balance
FROM customer_features cf
LEFT JOIN gender_medians_all gm ON cf.gender = gm.gender
GROUP BY cf.gender, gm.median_balance

UNION ALL

SELECT 
    'Txn Count = 1' AS cohort,
    cf.gender,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features WHERE txn_count = 1), 2) AS pct_customers,
    ROUND(SUM(cf.total_spend) / SUM(cf.txn_count), 2) AS avg_amount_per_txn,
    gms.median_balance
FROM customer_features cf
LEFT JOIN gender_medians_single gms ON cf.gender = gms.gender
WHERE cf.txn_count = 1
GROUP BY cf.gender, gms.median_balance

ORDER BY cohort, customers DESC;

-- Q6: Compare August and September average transactions and value per ACTIVE date.
-- Finding Note: The per-active-date volume drop from August (21,076.65) to September (17,759.14) is real in the data (-15.7%),
-- but its root cause is unknown. October is incomplete (only 2 active dates: 16 and 21 Oct) and is NOT used for trend comparison.
WITH monthly_metrics AS (
    SELECT 
        DATE_FORMAT(transaction_date, '%Y-%m') AS txn_month,
        COUNT(DISTINCT transaction_date) AS active_dates,
        COUNT(*) AS total_txns,
        ROUND(SUM(amount), 2) AS total_value,
        ROUND(COUNT(*) / COUNT(DISTINCT transaction_date), 2) AS avg_txns_per_active_date,
        ROUND(SUM(amount) / COUNT(DISTINCT transaction_date), 2) AS avg_value_per_active_date
    FROM transactions
    GROUP BY DATE_FORMAT(transaction_date, '%Y-%m')
)
SELECT 
    txn_month,
    active_dates,
    total_txns,
    total_value,
    avg_txns_per_active_date,
    avg_value_per_active_date,
    CASE 
        WHEN txn_month = '2016-10' THEN 'Incomplete (2 active dates; not used for trend comparison)'
        WHEN txn_month = '2016-08' THEN 'Full month (31 active dates)'
        WHEN txn_month = '2016-09' THEN '22 active dates (8 missing calendar dates)'
    END AS note
FROM monthly_metrics
ORDER BY txn_month;

-- Q7: Busiest Hour of Day and Day of Week.
-- For day of week, uses August only (all 31 dates active) for fair per-day normalization.
-- Part A: Top 5 Hours of the Day
SELECT 
    transaction_hour,
    COUNT(*) AS txn_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM transactions), 2) AS pct_txns,
    ROUND(SUM(amount), 2) AS total_value
FROM transactions
WHERE transaction_hour IS NOT NULL
GROUP BY transaction_hour
ORDER BY txn_count DESC
LIMIT 5;

-- Part B: Day of Week (August Only - all 31 dates active)
WITH aug_txns AS (
    SELECT 
        transaction_date,
        day_of_week,
        COUNT(*) AS daily_txns,
        SUM(amount) AS daily_val
    FROM transactions
    WHERE transaction_date BETWEEN '2016-08-01' AND '2016-08-31'
    GROUP BY transaction_date, day_of_week
)
SELECT 
    day_of_week,
    COUNT(DISTINCT transaction_date) AS dates_count,
    SUM(daily_txns) AS total_txns,
    ROUND(SUM(daily_txns) * 100.0 / (SELECT COUNT(*) FROM transactions WHERE transaction_date BETWEEN '2016-08-01' AND '2016-08-31'), 2) AS pct_aug_txns,
    ROUND(SUM(daily_txns) / COUNT(DISTINCT transaction_date), 2) AS avg_txns_per_date,
    ROUND(SUM(daily_val), 2) AS total_value,
    ROUND(SUM(daily_val) / COUNT(DISTINCT transaction_date), 2) AS avg_val_per_date
FROM aug_txns
GROUP BY day_of_week
ORDER BY 
    CASE day_of_week
        WHEN 'Monday' THEN 1
        WHEN 'Tuesday' THEN 2
        WHEN 'Wednesday' THEN 3
        WHEN 'Thursday' THEN 4
        WHEN 'Friday' THEN 5
        WHEN 'Saturday' THEN 6
        WHEN 'Sunday' THEN 7
    END;

-- Q8: High balance but low activity customers (cross-sell targets).
-- Filter Criteria: exactly balance_pr >= 0.70 AND spend_pr <= 0.30 AND txn_count = 1 AND profile_conflict_flag = 0.
-- Shows target customer count, median balance, average balance, and the exact balance and spend cutoffs in rupees.
WITH ranked_all AS (
    SELECT 
        customer_id,
        latest_balance,
        total_spend,
        txn_count,
        profile_conflict_flag,
        CASE 
            WHEN latest_balance IS NULL THEN NULL
            ELSE PERCENT_RANK() OVER (
                PARTITION BY (CASE WHEN latest_balance IS NOT NULL THEN 1 ELSE 0 END) 
                ORDER BY latest_balance
            )
        END AS balance_pr,
        PERCENT_RANK() OVER (ORDER BY total_spend) AS spend_pr
    FROM customer_features
),
cutoffs AS (
    SELECT 
        (SELECT MIN(latest_balance) FROM ranked_all WHERE balance_pr >= 0.70) AS balance_cutoff_p70,
        (SELECT MAX(total_spend) FROM ranked_all WHERE spend_pr <= 0.30) AS spend_cutoff_p30
    FROM ranked_all
    LIMIT 1
),
target_custs AS (
    SELECT 
        r.customer_id,
        r.latest_balance,
        r.total_spend
    FROM ranked_all r
    WHERE r.balance_pr >= 0.70 
      AND r.spend_pr <= 0.30 
      AND r.txn_count = 1 
      AND r.profile_conflict_flag = 0
),
bal_ranked AS (
    SELECT 
        latest_balance,
        ROW_NUMBER() OVER (ORDER BY latest_balance) AS rn,
        COUNT(*) OVER () AS cnt
    FROM target_custs
)
SELECT 
    COUNT(*) AS target_customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features), 2) AS pct_of_all_customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features WHERE txn_count = 1 AND profile_conflict_flag = 0), 2) AS pct_of_unflagged_single_txn,
    (SELECT balance_cutoff_p70 FROM cutoffs) AS balance_cutoff_p70,
    (SELECT spend_cutoff_p30 FROM cutoffs) AS spend_cutoff_p30,
    (SELECT ROUND(AVG(latest_balance), 2) FROM bal_ranked WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))) AS median_balance,
    ROUND(AVG(latest_balance), 2) AS avg_balance,
    ROUND(AVG(total_spend), 2) AS avg_spend,
    ROUND(SUM(latest_balance), 2) AS total_held_balance
FROM target_custs;

-- Q9: Top 3 customers by total_spend in each of the top 5 locations, excluding flagged customers.
-- Excludes 'OTHER' and customers with profile_conflict_flag = 1.
WITH top5_locs AS (
    SELECT location_clean
    FROM customer_features
    WHERE location_clean NOT IN ('OTHER')
    GROUP BY location_clean
    ORDER BY SUM(total_spend) DESC
    LIMIT 5
),
ranked_unflagged AS (
    SELECT 
        cf.location_clean,
        cf.customer_id,
        cf.total_spend,
        cf.txn_count,
        cf.latest_balance,
        DENSE_RANK() OVER (PARTITION BY cf.location_clean ORDER BY cf.total_spend DESC) AS spend_rank
    FROM customer_features cf
    JOIN top5_locs tl ON cf.location_clean = tl.location_clean
    WHERE cf.profile_conflict_flag = 0
)
SELECT 
    location_clean,
    spend_rank,
    customer_id,
    total_spend,
    txn_count,
    latest_balance
FROM ranked_unflagged
WHERE spend_rank <= 3
ORDER BY location_clean, spend_rank;

-- Q10: Customers and spend share by value_segment AND by rfm_segment, with flagged vs not flagged.
-- Part A: Value Segments Flagged (flag=1) vs Not Flagged (flag=0)
SELECT 
    'Value Segment' AS segment_type,
    value_segment AS segment_name,
    profile_conflict_flag,
    CASE WHEN profile_conflict_flag = 1 THEN 'Flagged (Conflict)' ELSE 'Not Flagged (Clean)' END AS flag_status,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_segments), 2) AS pct_total_customers,
    ROUND(SUM(total_spend), 2) AS total_spend,
    ROUND(SUM(total_spend) * 100.0 / (SELECT SUM(total_spend) FROM customer_segments), 2) AS pct_total_spend,
    ROUND(AVG(total_spend), 2) AS avg_spend_per_cust
FROM customer_segments
GROUP BY value_segment, profile_conflict_flag
ORDER BY 
    CASE value_segment 
        WHEN 'Premium' THEN 1
        WHEN 'High' THEN 2
        WHEN 'Mid' THEN 3
        WHEN 'Low' THEN 4
        WHEN 'Unknown balance' THEN 5
    END,
    profile_conflict_flag DESC;

-- Part B: RFM Segments Flagged (flag=1) vs Not Flagged (flag=0)
SELECT 
    'RFM Segment' AS segment_type,
    rfm_segment AS segment_name,
    profile_conflict_flag,
    CASE WHEN profile_conflict_flag = 1 THEN 'Flagged (Conflict)' ELSE 'Not Flagged (Clean)' END AS flag_status,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_segments), 2) AS pct_total_customers,
    ROUND(SUM(total_spend), 2) AS total_spend,
    ROUND(SUM(total_spend) * 100.0 / (SELECT SUM(total_spend) FROM customer_segments), 2) AS pct_total_spend,
    ROUND(AVG(total_spend), 2) AS avg_spend_per_cust
FROM customer_segments
GROUP BY rfm_segment, profile_conflict_flag
ORDER BY 
    CASE rfm_segment 
        WHEN 'Champions' THEN 1
        WHEN 'Loyal' THEN 2
        WHEN 'One-time Higher Spenders' THEN 3
        WHEN 'Recent Light' THEN 4
        WHEN 'Last seen before mid-Aug (45+ days)' THEN 5
        WHEN 'Others' THEN 6
    END,
    profile_conflict_flag DESC;

-- Q11: Running total and 7-active-day moving average of daily transaction value.
-- Note: 27 calendar dates are missing in the dataset, so the moving average reflects the last 7 active dates.
WITH daily_txns AS (
    SELECT 
        transaction_date,
        COUNT(*) AS daily_count,
        ROUND(SUM(amount), 2) AS daily_val
    FROM transactions
    GROUP BY transaction_date
)
SELECT 
    transaction_date,
    daily_count,
    daily_val,
    ROUND(SUM(daily_val) OVER (ORDER BY transaction_date), 2) AS running_val,
    ROUND(AVG(daily_val) OVER (
        ORDER BY transaction_date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_7_active_days_val,
    ROUND(AVG(daily_count) OVER (
        ORDER BY transaction_date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_7_active_days_count
FROM daily_txns
ORDER BY transaction_date;

-- =====================================================================
-- SUPPLEMENTARY / ROBUSTNESS QUERIES
-- =====================================================================

-- Supplementary Query A: Missing calendar dates in transactions (August to October 2016)
-- Generates full calendar series and identifies all 27 missing dates (8 in Sep, 19 in Oct).
WITH RECURSIVE calendar AS (
    SELECT DATE('2016-08-01') AS cal_date
    UNION ALL
    SELECT DATE_ADD(cal_date, INTERVAL 1 DAY)
    FROM calendar
    WHERE cal_date < '2016-10-21'
)
SELECT 
    cal_date AS calendar_date,
    DAYNAME(cal_date) AS day_of_week
FROM calendar
WHERE cal_date NOT IN (SELECT DISTINCT transaction_date FROM transactions)
ORDER BY calendar_date;

-- Supplementary Query B: Raw staging transaction records for Kolkata suspect accounts
-- Inspects raw data for the 3 accounts sharing identical DOB (1800) and balance (157,333.33).
SELECT 
    transaction_id,
    customer_id,
    customer_dob,
    cust_gender,
    cust_location,
    cust_account_balance,
    transaction_date,
    transaction_time,
    transaction_amount
FROM staging_bank_transactions
WHERE customer_id IN ('C1525358', 'C6825363', 'C7525325')
ORDER BY customer_id, transaction_date;

-- Supplementary Query C: Robustness Check - Age x Gender Demographics
-- Compares the full population against single-transaction customers (100% clean profile baseline).
WITH cohort_data AS (
    SELECT 
        'All Customers' AS cohort,
        age_group,
        gender,
        customer_id,
        total_spend,
        txn_count,
        latest_balance
    FROM customer_features
    UNION ALL
    SELECT 
        'Txn Count = 1' AS cohort,
        age_group,
        gender,
        customer_id,
        total_spend,
        txn_count,
        latest_balance
    FROM customer_features
    WHERE txn_count = 1
),
ranked_spend AS (
    SELECT 
        cohort,
        age_group,
        gender,
        total_spend,
        ROW_NUMBER() OVER (PARTITION BY cohort, age_group, gender ORDER BY total_spend) AS rn_spend,
        COUNT(*) OVER (PARTITION BY cohort, age_group, gender) AS cnt_spend
    FROM cohort_data
),
spend_med AS (
    SELECT 
        cohort,
        age_group,
        gender,
        ROUND(AVG(total_spend), 2) AS median_spend
    FROM ranked_spend
    WHERE rn_spend IN (FLOOR((cnt_spend + 1) / 2), CEIL((cnt_spend + 1) / 2))
    GROUP BY cohort, age_group, gender
),
ranked_bal AS (
    SELECT 
        cohort,
        age_group,
        gender,
        latest_balance,
        ROW_NUMBER() OVER (PARTITION BY cohort, age_group, gender ORDER BY latest_balance) AS rn_bal,
        COUNT(*) OVER (PARTITION BY cohort, age_group, gender) AS cnt_bal
    FROM cohort_data
    WHERE latest_balance IS NOT NULL
),
bal_med AS (
    SELECT 
        cohort,
        age_group,
        gender,
        ROUND(AVG(latest_balance), 2) AS median_balance
    FROM ranked_bal
    WHERE rn_bal IN (FLOOR((cnt_bal + 1) / 2), CEIL((cnt_bal + 1) / 2))
    GROUP BY cohort, age_group, gender
)
SELECT 
    c.cohort,
    c.age_group,
    c.gender,
    COUNT(c.customer_id) AS customers,
    ROUND(SUM(c.total_spend) / SUM(c.txn_count), 2) AS avg_amount_per_txn,
    sm.median_spend,
    bm.median_balance
FROM cohort_data c
LEFT JOIN spend_med sm ON c.cohort = sm.cohort AND c.age_group = sm.age_group AND c.gender = sm.gender
LEFT JOIN bal_med bm ON c.cohort = bm.cohort AND c.age_group = bm.age_group AND c.gender = bm.gender
GROUP BY c.cohort, c.age_group, c.gender, sm.median_spend, bm.median_balance
ORDER BY 
    CASE c.cohort WHEN 'All Customers' THEN 1 ELSE 2 END,
    CASE c.age_group 
        WHEN '18-25' THEN 1 
        WHEN '26-35' THEN 2 
        WHEN '36-45' THEN 3 
        WHEN '46-60' THEN 4 
        WHEN '60+' THEN 5 
        ELSE 6 
    END,
    c.gender;

-- Supplementary Query D: Robustness Check - Value Segments Summary across cohorts
-- Validates value segments across All Customers, Conflict Flag = 0, and Single-Transaction baseline.
WITH cohorts AS (
    SELECT 'All Customers' AS cohort, value_segment, customer_id, total_spend, latest_balance FROM customer_segments
    UNION ALL
    SELECT 'Conflict Flag = 0' AS cohort, value_segment, customer_id, total_spend, latest_balance FROM customer_segments WHERE profile_conflict_flag = 0
    UNION ALL
    SELECT 'Txn Count = 1' AS cohort, cs.value_segment, cs.customer_id, cs.total_spend, cs.latest_balance 
    FROM customer_segments cs 
    JOIN customer_features cf ON cs.customer_id = cf.customer_id 
    WHERE cf.txn_count = 1
),
ranked_spend AS (
    SELECT 
        cohort,
        value_segment,
        total_spend,
        ROW_NUMBER() OVER (PARTITION BY cohort, value_segment ORDER BY total_spend) AS rn_s,
        COUNT(*) OVER (PARTITION BY cohort, value_segment) AS cnt_s
    FROM cohorts
),
spend_med AS (
    SELECT 
        cohort,
        value_segment,
        ROUND(AVG(total_spend), 2) AS median_spend
    FROM ranked_spend
    WHERE rn_s IN (FLOOR((cnt_s + 1) / 2), CEIL((cnt_s + 1) / 2))
    GROUP BY cohort, value_segment
),
ranked_bal AS (
    SELECT 
        cohort,
        value_segment,
        latest_balance,
        ROW_NUMBER() OVER (PARTITION BY cohort, value_segment ORDER BY latest_balance) AS rn_b,
        COUNT(*) OVER (PARTITION BY cohort, value_segment) AS cnt_b
    FROM cohorts
    WHERE latest_balance IS NOT NULL
),
bal_med AS (
    SELECT 
        cohort,
        value_segment,
        ROUND(AVG(latest_balance), 2) AS median_balance
    FROM ranked_bal
    WHERE rn_b IN (FLOOR((cnt_b + 1) / 2), CEIL((cnt_b + 1) / 2))
    GROUP BY cohort, value_segment
)
SELECT 
    c.cohort,
    c.value_segment,
    COUNT(c.customer_id) AS customers,
    ROUND(AVG(c.total_spend), 2) AS avg_spend,
    sm.median_spend,
    bm.median_balance
FROM cohorts c
LEFT JOIN spend_med sm ON c.cohort = sm.cohort AND c.value_segment = sm.value_segment
LEFT JOIN bal_med bm ON c.cohort = bm.cohort AND c.value_segment = bm.value_segment
GROUP BY c.cohort, c.value_segment, sm.median_spend, bm.median_balance
ORDER BY 
    CASE c.cohort 
        WHEN 'All Customers' THEN 1 
        WHEN 'Conflict Flag = 0' THEN 2 
        WHEN 'Txn Count = 1' THEN 3 
    END,
    CASE c.value_segment 
        WHEN 'Premium' THEN 1 
        WHEN 'High' THEN 2 
        WHEN 'Mid' THEN 3 
        WHEN 'Low' THEN 4 
        WHEN 'Unknown balance' THEN 5 
    END;

