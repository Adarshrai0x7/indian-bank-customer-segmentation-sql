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

-- Q1: What % of total transaction value comes from the top 10% of customers?
-- Divides customers into 10 deciles by spend using NTILE(10) and sums spend per decile.
WITH ranked_customers AS (
    SELECT 
        customer_id,
        total_spend,
        NTILE(10) OVER (ORDER BY total_spend DESC) AS spend_decile
    FROM customer_features
)
SELECT 
    spend_decile,
    COUNT(*) AS customers,
    ROUND(SUM(total_spend), 2) AS decile_spend,
    ROUND(SUM(total_spend) * 100.0 / (SELECT SUM(total_spend) FROM customer_features), 2) AS pct_total_spend
FROM ranked_customers
GROUP BY spend_decile
ORDER BY spend_decile;

-- Q2: Which age group has the highest average balance and highest average spend?
-- Compares customer count, average balance, average spend, and total spend across age cohorts.
SELECT 
    age_group,
    COUNT(*) AS total_customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features), 2) AS pct_customers,
    ROUND(AVG(latest_balance), 2) AS avg_balance,
    ROUND(AVG(total_spend), 2) AS avg_spend,
    ROUND(SUM(total_spend), 2) AS total_spend
FROM customer_features
GROUP BY age_group
ORDER BY avg_spend DESC;

-- Q3: Top 10 locations by customer count and by total transaction value.
-- Groups cleaned locations to rank geography by both customer presence and transaction volume.
SELECT 
    location_clean,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features), 2) AS pct_customers,
    ROUND(SUM(total_spend), 2) AS total_spend,
    ROUND(SUM(total_spend) * 100.0 / (SELECT SUM(total_spend) FROM customer_features), 2) AS pct_total_spend,
    ROUND(AVG(total_spend), 2) AS avg_spend_per_customer
FROM customer_features
GROUP BY location_clean
ORDER BY total_spend DESC
LIMIT 10;

-- Q4: Customers with no transaction in September or October (August only).
-- Identifies inactive customers post-August and tallies their count, customer share, and held balance.
SELECT 
    COUNT(*) AS august_only_customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features), 2) AS pct_customers,
    ROUND(SUM(latest_balance), 2) AS total_latest_balance,
    ROUND(AVG(latest_balance), 2) AS avg_latest_balance,
    COUNT(CASE WHEN latest_balance IS NULL THEN 1 END) AS null_balance_count
FROM customer_features
WHERE last_txn_date <= '2016-08-31';

-- Q5: Gender split: customers, avg spend, and avg balance.
-- Shows demographic split across all customers including customer volume and balances.
SELECT 
    gender,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features), 2) AS pct_customers,
    ROUND(AVG(latest_balance), 2) AS avg_balance,
    ROUND(AVG(total_spend), 2) AS avg_spend,
    ROUND(SUM(total_spend), 2) AS total_spend,
    ROUND(SUM(total_spend) * 100.0 / (SELECT SUM(total_spend) FROM customer_features), 2) AS pct_total_spend
FROM customer_features
GROUP BY gender
ORDER BY customer_count DESC;

-- Q6: Compare August and September average transactions and value per ACTIVE date.
-- Displays October as 'partial: 2 days of data' to avoid false decline conclusions.
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
        WHEN txn_month = '2016-10' THEN 'partial: 2 days of data'
        ELSE 'full month'
    END AS data_status
FROM monthly_metrics
ORDER BY txn_month;

-- Q7: Which hour of day and which day of week are the busiest?
-- Aggregates volume by hour of day (top 5) and by day of the week.
SELECT 
    'Hour of Day' AS category,
    CAST(transaction_hour AS CHAR) AS time_unit,
    COUNT(*) AS txn_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM transactions), 2) AS pct_txns,
    ROUND(SUM(amount), 2) AS total_value
FROM transactions
WHERE transaction_hour IS NOT NULL
GROUP BY transaction_hour
ORDER BY txn_count DESC
LIMIT 5;

SELECT 
    'Day of Week' AS category,
    day_of_week AS time_unit,
    COUNT(*) AS txn_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM transactions), 2) AS pct_txns,
    ROUND(SUM(amount), 2) AS total_value
FROM transactions
WHERE day_of_week IS NOT NULL
GROUP BY day_of_week
ORDER BY txn_count DESC;

-- Q8: High balance but low activity customers (cross-sell targets).
-- Defines high balance as top quartile (>=75%) and low activity as bottom spend quartile (<=25%).
WITH customer_ranks AS (
    SELECT 
        customer_id,
        latest_balance,
        total_spend,
        txn_count,
        CASE 
            WHEN latest_balance IS NULL THEN NULL
            ELSE PERCENT_RANK() OVER (
                PARTITION BY (CASE WHEN latest_balance IS NOT NULL THEN 1 ELSE 0 END) 
                ORDER BY latest_balance
            )
        END AS bal_pr,
        PERCENT_RANK() OVER (ORDER BY total_spend) AS spend_pr
    FROM customer_features
)
SELECT 
    COUNT(*) AS target_customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features), 2) AS pct_total_customers,
    ROUND(AVG(latest_balance), 2) AS avg_balance,
    ROUND(AVG(total_spend), 2) AS avg_spend,
    ROUND(SUM(latest_balance), 2) AS total_held_balance
FROM customer_ranks
WHERE bal_pr >= 0.75 AND spend_pr <= 0.25;

-- Q9: Rank customers by spend inside each of the top 5 locations.
-- Uses DENSE_RANK() with PARTITION BY location to find top 3 spenders per metro hub.
WITH top5_locs AS (
    SELECT location_clean
    FROM customer_features
    GROUP BY location_clean
    ORDER BY SUM(total_spend) DESC
    LIMIT 5
),
ranked_custs AS (
    SELECT 
        cf.location_clean,
        cf.customer_id,
        cf.total_spend,
        cf.txn_count,
        cf.latest_balance,
        DENSE_RANK() OVER (PARTITION BY cf.location_clean ORDER BY cf.total_spend DESC) AS spend_rank
    FROM customer_features cf
    JOIN top5_locs tl ON cf.location_clean = tl.location_clean
)
SELECT 
    location_clean,
    spend_rank,
    customer_id,
    total_spend,
    txn_count,
    latest_balance
FROM ranked_custs
WHERE spend_rank <= 3
ORDER BY location_clean, spend_rank;

-- Q10: Which RFM segment contributes the most spend and which has the most customers?
-- Aggregates customer count and revenue share across the 6 mutually exclusive RFM segments.
SELECT 
    rfm_segment,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_segments), 2) AS pct_customers,
    ROUND(SUM(total_spend), 2) AS total_spend,
    ROUND(SUM(total_spend) * 100.0 / (SELECT SUM(total_spend) FROM customer_segments), 2) AS pct_total_spend,
    ROUND(AVG(total_spend), 2) AS avg_spend_per_cust
FROM customer_segments
GROUP BY rfm_segment
ORDER BY total_spend DESC;

-- Q11 (Bonus): Running total of daily transaction value.
-- Calculates progressive cumulative transaction revenue using SUM() OVER (ORDER BY date).
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
    ROUND(SUM(daily_val) OVER (ORDER BY transaction_date), 2) AS running_val
FROM daily_txns
ORDER BY transaction_date;

-- Q12 (Bonus): Customers whose spending increased month-over-month.
-- Evaluates multi-month transaction growth using monthly aggregations and conditional filters.
WITH monthly_cust_spend AS (
    SELECT 
        customer_id,
        DATE_FORMAT(transaction_date, '%Y-%m') AS txn_month,
        SUM(amount) AS month_spend
    FROM transactions
    GROUP BY customer_id, DATE_FORMAT(transaction_date, '%Y-%m')
),
spend_pivoted AS (
    SELECT 
        customer_id,
        MAX(CASE WHEN txn_month = '2016-08' THEN month_spend ELSE 0 END) AS aug_spend,
        MAX(CASE WHEN txn_month = '2016-09' THEN month_spend ELSE 0 END) AS sep_spend,
        MAX(CASE WHEN txn_month = '2016-10' THEN month_spend ELSE 0 END) AS oct_spend,
        COUNT(DISTINCT txn_month) AS active_month_count
    FROM monthly_cust_spend
    GROUP BY customer_id
)
SELECT 
    COUNT(CASE WHEN active_month_count = 3 AND aug_spend < sep_spend AND sep_spend < oct_spend THEN 1 END) AS strictly_increasing_all_3_months,
    COUNT(CASE WHEN aug_spend > 0 AND sep_spend > aug_spend THEN 1 END) AS increasing_aug_to_sep,
    COUNT(CASE WHEN active_month_count >= 2 THEN 1 END) AS multi_month_customers,
    COUNT(*) AS total_customers
FROM spend_pivoted;
