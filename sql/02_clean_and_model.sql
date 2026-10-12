-- ============================================================================
-- Phase 2: Data Cleaning and Dimensional Modeling
-- Script: sql/02_clean_and_model.sql
-- Database: MySQL 8.0+
-- Reference Date for all age calculations: 2016-10-21 (max date in dataset)
-- ============================================================================

-- Step 1: Create city lookup table to group location strings into major metro areas.
-- Groups messy variations into 30+ economic centers, international hubs, and OTHER.
DROP TABLE IF EXISTS city_lookup;
CREATE TABLE city_lookup (
    lookup_id       INT AUTO_INCREMENT PRIMARY KEY,
    pattern         VARCHAR(50) NOT NULL,
    standard_city   VARCHAR(50) NOT NULL,
    priority        INT NOT NULL
);

-- Step 2: Populate lookup patterns for tier-1/tier-2 cities and international keywords.
-- Priority ensures specific metro regions match before broad fallback rules.
INSERT INTO city_lookup (pattern, standard_city, priority) VALUES
('%MUMBAI%', 'MUMBAI METRO', 1),
('%THANE%', 'MUMBAI METRO', 1),
('%NAVI MUMBAI%', 'MUMBAI METRO', 1),
('%DELHI%', 'DELHI NCR', 1),
('%GURGAON%', 'DELHI NCR', 1),
('%GURUGRAM%', 'DELHI NCR', 1),
('%NOIDA%', 'DELHI NCR', 1),
('%FARIDABAD%', 'DELHI NCR', 1),
('%GHAZIABAD%', 'DELHI NCR', 1),
('%BANGALORE%', 'BANGALORE', 1),
('%BENGALURU%', 'BANGALORE', 1),
('%CHENNAI%', 'CHENNAI', 1),
('%MADRAS%', 'CHENNAI', 1),
('%HYDERABAD%', 'HYDERABAD', 1),
('%SECUNDERABAD%', 'HYDERABAD', 1),
('%PUNE%', 'PUNE', 1),
('%KOLKATA%', 'KOLKATA', 1),
('%CALCUTTA%', 'KOLKATA', 1),
('%AHMEDABAD%', 'AHMEDABAD', 1),
('%JAIPUR%', 'JAIPUR', 1),
('%CHANDIGARH%', 'CHANDIGARH TRICITY', 1),
('%MOHALI%', 'CHANDIGARH TRICITY', 1),
('%PANCHKULA%', 'CHANDIGARH TRICITY', 1),
('%LUCKNOW%', 'LUCKNOW', 1),
('%COIMBATORE%', 'COIMBATORE', 1),
('%SURAT%', 'SURAT', 1),
('%INDORE%', 'INDORE', 1),
('%NAGPUR%', 'NAGPUR', 1),
('%VADODARA%', 'VADODARA', 1),
('%BARODA%', 'VADODARA', 1),
('%BHOPAL%', 'BHOPAL', 1),
('%VISAKHAPATNAM%', 'VISAKHAPATNAM', 1),
('%VIZAG%', 'VISAKHAPATNAM', 1),
('%KOCHI%', 'KOCHI', 1),
('%COCHIN%', 'KOCHI', 1),
('%ERNAKULAM%', 'KOCHI', 1),
('%PATNA%', 'PATNA', 1),
('%LUDHIANA%', 'LUDHIANA', 1),
('%KANPUR%', 'KANPUR', 1),
('%AGRA%', 'AGRA', 1),
('%NASHIK%', 'NASHIK', 1),
('%VARANASI%', 'VARANASI', 1),
('%AMRITSAR%', 'AMRITSAR', 1),
('%RAJKOT%', 'RAJKOT', 1),
('%RANCHI%', 'RANCHI', 1),
('%BHUBANESWAR%', 'BHUBANESWAR', 1),
('%DEHRADUN%', 'DEHRADUN', 1),
('%JAMSHEDPUR%', 'JAMSHEDPUR', 1),
('%MANGALORE%', 'MANGALORE', 1),
('%GUWAHATI%', 'GUWAHATI', 1),
('%PO BOX%', 'INTERNATIONAL', 2),
('%DUBAI%', 'INTERNATIONAL', 2),
('%RIYADH%', 'INTERNATIONAL', 2),
('%DOHA%', 'INTERNATIONAL', 2),
('%ABU DHABI%', 'INTERNATIONAL', 2),
('%SINGAPORE%', 'INTERNATIONAL', 2),
('%SHARJAH%', 'INTERNATIONAL', 2),
('%KUWAIT%', 'INTERNATIONAL', 2),
('%BAHRAIN%', 'INTERNATIONAL', 2),
('%MUSCAT%', 'INTERNATIONAL', 2),
('%QATAR%', 'INTERNATIONAL', 2),
('%LONDON%', 'INTERNATIONAL', 2);

-- Step 3: Create clean transactions fact table with typed columns and indexes.
-- Stores valid transactions with converted dates, times, and decimal amounts.
DROP TABLE IF EXISTS transactions;
CREATE TABLE transactions (
    transaction_id     VARCHAR(50) PRIMARY KEY,
    customer_id        VARCHAR(50) NOT NULL,
    transaction_date   DATE NOT NULL,
    transaction_time   TIME NULL,
    transaction_hour   TINYINT NULL,
    day_of_week        VARCHAR(20) NULL,
    month_label        VARCHAR(10) NULL,
    amount             DECIMAL(15,2) NOT NULL,
    account_balance    DECIMAL(15,2) NULL,
    INDEX idx_txn_customer (customer_id),
    INDEX idx_txn_date (transaction_date)
);

-- Step 4: Populate transactions table from staging, excluding zero amounts and null keys.
-- Zero amounts (835 rows) are excluded (reason unknown) and blank balances become NULL.
INSERT INTO transactions (
    transaction_id,
    customer_id,
    transaction_date,
    transaction_time,
    transaction_hour,
    day_of_week,
    month_label,
    amount,
    account_balance
)
SELECT 
    transaction_id,
    customer_id,
    STR_TO_DATE(TRIM(transaction_date), '%d/%m/%y') AS transaction_date,
    TIME(STR_TO_DATE(LPAD(TRIM(transaction_time), 6, '0'), '%H%i%s')) AS transaction_time,
    HOUR(STR_TO_DATE(LPAD(TRIM(transaction_time), 6, '0'), '%H%i%s')) AS transaction_hour,
    DAYNAME(STR_TO_DATE(TRIM(transaction_date), '%d/%m/%y')) AS day_of_week,
    DATE_FORMAT(STR_TO_DATE(TRIM(transaction_date), '%d/%m/%y'), '%Y-%m') AS month_label,
    CAST(TRIM(transaction_amount) AS DECIMAL(15,2)) AS amount,
    CASE 
        WHEN cust_account_balance IS NULL OR TRIM(cust_account_balance) = '' THEN NULL 
        ELSE CAST(TRIM(cust_account_balance) AS DECIMAL(15,2)) 
    END AS account_balance
FROM staging_bank_transactions
WHERE customer_id IS NOT NULL AND TRIM(customer_id) != ''
  AND transaction_date IS NOT NULL AND TRIM(transaction_date) != ''
  AND transaction_amount IS NOT NULL AND TRIM(transaction_amount) != ''
  AND CAST(TRIM(transaction_amount) AS DECIMAL(15,2)) > 0;

-- Step 5: Build intermediate staging table with cleaned and parsed customer attributes.
-- Manual DOB parsing ensures 2-digit years and placeholder dates (1/1/1800, nan) are handled safely.
DROP TABLE IF EXISTS stage_clean_txns;
CREATE TABLE stage_clean_txns (
    transaction_id         VARCHAR(50),
    customer_id            VARCHAR(50),
    txn_date               DATE,
    gender                 VARCHAR(20),
    dob                    DATE NULL,
    age                    INT NULL,
    raw_location           VARCHAR(255),
    balance                DECIMAL(15,2) NULL,
    INDEX idx_sct_cust (customer_id),
    INDEX idx_sct_cust_date (customer_id, txn_date, transaction_id)
) AS
SELECT 
    transaction_id,
    customer_id,
    STR_TO_DATE(TRIM(transaction_date), '%d/%m/%y') AS txn_date,
    CASE 
        WHEN UPPER(TRIM(cust_gender)) = 'M' THEN 'M'
        WHEN UPPER(TRIM(cust_gender)) = 'F' THEN 'F'
        ELSE 'Unknown'
    END AS gender,
    CASE 
        WHEN customer_dob IS NULL 
          OR TRIM(customer_dob) = '' 
          OR LOWER(TRIM(customer_dob)) = 'nan'
          OR TRIM(customer_dob) = '1/1/1800' 
          OR customer_dob NOT LIKE '%/%/%' THEN NULL
        WHEN CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED) = 1800 THEN NULL
        WHEN TIMESTAMPDIFF(YEAR, STR_TO_DATE(CONCAT(
            CASE 
                WHEN CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED) >= 17 
                THEN 1900 + CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED)
                ELSE 2000 + CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED)
            END, '-',
            LPAD(SUBSTRING_INDEX(SUBSTRING_INDEX(customer_dob, '/', 2), '/', -1), 2, '0'), '-',
            LPAD(SUBSTRING_INDEX(customer_dob, '/', 1), 2, '0')
        ), '%Y-%m-%d'), '2016-10-21') < 18 
          OR TIMESTAMPDIFF(YEAR, STR_TO_DATE(CONCAT(
            CASE 
                WHEN CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED) >= 17 
                THEN 1900 + CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED)
                ELSE 2000 + CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED)
            END, '-',
            LPAD(SUBSTRING_INDEX(SUBSTRING_INDEX(customer_dob, '/', 2), '/', -1), 2, '0'), '-',
            LPAD(SUBSTRING_INDEX(customer_dob, '/', 1), 2, '0')
        ), '%Y-%m-%d'), '2016-10-21') > 100 THEN NULL
        ELSE STR_TO_DATE(CONCAT(
            CASE 
                WHEN CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED) >= 17 
                THEN 1900 + CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED)
                ELSE 2000 + CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED)
            END, '-',
            LPAD(SUBSTRING_INDEX(SUBSTRING_INDEX(customer_dob, '/', 2), '/', -1), 2, '0'), '-',
            LPAD(SUBSTRING_INDEX(customer_dob, '/', 1), 2, '0')
        ), '%Y-%m-%d')
    END AS dob,
    CASE 
        WHEN customer_dob IS NULL 
          OR TRIM(customer_dob) = '' 
          OR LOWER(TRIM(customer_dob)) = 'nan'
          OR TRIM(customer_dob) = '1/1/1800' 
          OR customer_dob NOT LIKE '%/%/%' THEN NULL
        WHEN CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED) = 1800 THEN NULL
        WHEN TIMESTAMPDIFF(YEAR, STR_TO_DATE(CONCAT(
            CASE 
                WHEN CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED) >= 17 
                THEN 1900 + CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED)
                ELSE 2000 + CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED)
            END, '-',
            LPAD(SUBSTRING_INDEX(SUBSTRING_INDEX(customer_dob, '/', 2), '/', -1), 2, '0'), '-',
            LPAD(SUBSTRING_INDEX(customer_dob, '/', 1), 2, '0')
        ), '%Y-%m-%d'), '2016-10-21') < 18 
          OR TIMESTAMPDIFF(YEAR, STR_TO_DATE(CONCAT(
            CASE 
                WHEN CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED) >= 17 
                THEN 1900 + CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED)
                ELSE 2000 + CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED)
            END, '-',
            LPAD(SUBSTRING_INDEX(SUBSTRING_INDEX(customer_dob, '/', 2), '/', -1), 2, '0'), '-',
            LPAD(SUBSTRING_INDEX(customer_dob, '/', 1), 2, '0')
        ), '%Y-%m-%d'), '2016-10-21') > 100 THEN NULL
        ELSE TIMESTAMPDIFF(YEAR, STR_TO_DATE(CONCAT(
            CASE 
                WHEN CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED) >= 17 
                THEN 1900 + CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED)
                ELSE 2000 + CAST(SUBSTRING_INDEX(customer_dob, '/', -1) AS UNSIGNED)
            END, '-',
            LPAD(SUBSTRING_INDEX(SUBSTRING_INDEX(customer_dob, '/', 2), '/', -1), 2, '0'), '-',
            LPAD(SUBSTRING_INDEX(customer_dob, '/', 1), 2, '0')
        ), '%Y-%m-%d'), '2016-10-21')
    END AS age,
    TRIM(cust_location) AS raw_location,
    CASE 
        WHEN cust_account_balance IS NULL OR TRIM(cust_account_balance) = '' THEN NULL
        ELSE CAST(TRIM(cust_account_balance) AS DECIMAL(15,2))
    END AS balance
FROM staging_bank_transactions
WHERE CAST(TRIM(transaction_amount) AS DECIMAL(15,2)) > 0;

-- Step 6: Resolve modal gender per customer, preferring valid ('M'/'F') over 'Unknown', and breaking ties by latest transaction.
-- Ensures customers with at least one valid gender record are never mapped to 'Unknown'.
DROP TABLE IF EXISTS cust_gender_mode;
CREATE TABLE cust_gender_mode (
    customer_id VARCHAR(50) PRIMARY KEY,
    gender VARCHAR(20)
) AS
SELECT customer_id, gender
FROM (
    SELECT customer_id, gender,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id 
               ORDER BY 
                   CASE WHEN gender IN ('M', 'F') THEN 1 ELSE 0 END DESC,
                   freq DESC, 
                   max_date DESC, 
                   max_id DESC
           ) AS rnk
    FROM (
        SELECT customer_id, gender, COUNT(*) AS freq, MAX(txn_date) AS max_date, MAX(transaction_id) AS max_id
        FROM stage_clean_txns
        GROUP BY customer_id, gender
    ) g
) gr
WHERE rnk = 1;

-- Step 7: Resolve modal DOB per customer, prioritizing valid dates and breaking ties using latest transaction.
-- Selects the most consistent birthday per customer and filters out placeholder records.
DROP TABLE IF EXISTS cust_dob_mode;
CREATE TABLE cust_dob_mode (
    customer_id VARCHAR(50) PRIMARY KEY,
    dob DATE NULL,
    age INT NULL
) AS
SELECT customer_id, dob, age
FROM (
    SELECT customer_id, dob, age,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id 
               ORDER BY 
                   CASE WHEN dob IS NOT NULL THEN 1 ELSE 0 END DESC,
                   freq DESC, 
                   max_date DESC, 
                   max_id DESC
           ) AS rnk
    FROM (
        SELECT customer_id, dob, age, COUNT(*) AS freq, MAX(txn_date) AS max_date, MAX(transaction_id) AS max_id
        FROM stage_clean_txns
        GROUP BY customer_id, dob, age
    ) d
) dr
WHERE rnk = 1;

-- Step 8: Standardize customer location into major metro clusters, resolving modal location per customer.
-- Groups raw strings into 30+ key metros, international accounts, or OTHER.
DROP TABLE IF EXISTS cust_loc_mode;
CREATE TABLE cust_loc_mode (
    customer_id VARCHAR(50) PRIMARY KEY,
    location_clean VARCHAR(50)
) AS
SELECT 
    customer_id,
    CASE 
        WHEN UPPER(raw_location) LIKE '%MUMBAI%' OR UPPER(raw_location) LIKE '%THANE%' OR UPPER(raw_location) LIKE '%NAVI MUMBAI%' THEN 'MUMBAI METRO'
        WHEN UPPER(raw_location) LIKE '%DELHI%' OR UPPER(raw_location) LIKE '%GURGAON%' OR UPPER(raw_location) LIKE '%GURUGRAM%' OR UPPER(raw_location) LIKE '%NOIDA%' OR UPPER(raw_location) LIKE '%FARIDABAD%' OR UPPER(raw_location) LIKE '%GHAZIABAD%' THEN 'DELHI NCR'
        WHEN UPPER(raw_location) LIKE '%BANGALORE%' OR UPPER(raw_location) LIKE '%BENGALURU%' THEN 'BANGALORE'
        WHEN UPPER(raw_location) LIKE '%CHENNAI%' OR UPPER(raw_location) LIKE '%MADRAS%' THEN 'CHENNAI'
        WHEN UPPER(raw_location) LIKE '%HYDERABAD%' OR UPPER(raw_location) LIKE '%SECUNDERABAD%' THEN 'HYDERABAD'
        WHEN UPPER(raw_location) LIKE '%PUNE%' THEN 'PUNE'
        WHEN UPPER(raw_location) LIKE '%KOLKATA%' OR UPPER(raw_location) LIKE '%CALCUTTA%' THEN 'KOLKATA'
        WHEN UPPER(raw_location) LIKE '%AHMEDABAD%' THEN 'AHMEDABAD'
        WHEN UPPER(raw_location) LIKE '%JAIPUR%' THEN 'JAIPUR'
        WHEN UPPER(raw_location) LIKE '%CHANDIGARH%' OR UPPER(raw_location) LIKE '%MOHALI%' OR UPPER(raw_location) LIKE '%PANCHKULA%' THEN 'CHANDIGARH TRICITY'
        WHEN UPPER(raw_location) LIKE '%LUCKNOW%' THEN 'LUCKNOW'
        WHEN UPPER(raw_location) LIKE '%COIMBATORE%' THEN 'COIMBATORE'
        WHEN UPPER(raw_location) LIKE '%SURAT%' THEN 'SURAT'
        WHEN UPPER(raw_location) LIKE '%INDORE%' THEN 'INDORE'
        WHEN UPPER(raw_location) LIKE '%NAGPUR%' THEN 'NAGPUR'
        WHEN UPPER(raw_location) LIKE '%VADODARA%' OR UPPER(raw_location) LIKE '%BARODA%' THEN 'VADODARA'
        WHEN UPPER(raw_location) LIKE '%BHOPAL%' THEN 'BHOPAL'
        WHEN UPPER(raw_location) LIKE '%VISAKHAPATNAM%' OR UPPER(raw_location) LIKE '%VIZAG%' THEN 'VISAKHAPATNAM'
        WHEN UPPER(raw_location) LIKE '%KOCHI%' OR UPPER(raw_location) LIKE '%COCHIN%' OR UPPER(raw_location) LIKE '%ERNAKULAM%' THEN 'KOCHI'
        WHEN UPPER(raw_location) LIKE '%PATNA%' THEN 'PATNA'
        WHEN UPPER(raw_location) LIKE '%LUDHIANA%' THEN 'LUDHIANA'
        WHEN UPPER(raw_location) LIKE '%KANPUR%' THEN 'KANPUR'
        WHEN UPPER(raw_location) LIKE '%AGRA%' THEN 'AGRA'
        WHEN UPPER(raw_location) LIKE '%NASHIK%' THEN 'NASHIK'
        WHEN UPPER(raw_location) LIKE '%VARANASI%' THEN 'VARANASI'
        WHEN UPPER(raw_location) LIKE '%AMRITSAR%' THEN 'AMRITSAR'
        WHEN UPPER(raw_location) LIKE '%RAJKOT%' THEN 'RAJKOT'
        WHEN UPPER(raw_location) LIKE '%RANCHI%' THEN 'RANCHI'
        WHEN UPPER(raw_location) LIKE '%BHUBANESWAR%' THEN 'BHUBANESWAR'
        WHEN UPPER(raw_location) LIKE '%DEHRADUN%' THEN 'DEHRADUN'
        WHEN UPPER(raw_location) LIKE '%JAMSHEDPUR%' THEN 'JAMSHEDPUR'
        WHEN UPPER(raw_location) LIKE '%MANGALORE%' THEN 'MANGALORE'
        WHEN UPPER(raw_location) LIKE '%GUWAHATI%' THEN 'GUWAHATI'
        WHEN UPPER(raw_location) LIKE '%PO BOX%' OR UPPER(raw_location) LIKE '%DUBAI%' OR UPPER(raw_location) LIKE '%RIYADH%' OR UPPER(raw_location) LIKE '%DOHA%' OR UPPER(raw_location) LIKE '%SINGAPORE%' OR UPPER(raw_location) LIKE '%SHARJAH%' OR UPPER(raw_location) LIKE '%ABU DHABI%' OR UPPER(raw_location) LIKE '%KUWAIT%' OR UPPER(raw_location) LIKE '%BAHRAIN%' OR UPPER(raw_location) LIKE '%MUSCAT%' OR UPPER(raw_location) LIKE '%QATAR%' OR UPPER(raw_location) LIKE '%LONDON%' THEN 'INTERNATIONAL'
        ELSE 'OTHER'
    END AS location_clean
FROM (
    SELECT customer_id, raw_location,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY freq DESC, max_date DESC, max_id DESC) AS rnk
    FROM (
        SELECT customer_id, raw_location, COUNT(*) AS freq, MAX(txn_date) AS max_date, MAX(transaction_id) AS max_id
        FROM stage_clean_txns
        GROUP BY customer_id, raw_location
    ) l
) lr
WHERE rnk = 1;

-- Step 9: Extract the most recent account balance per customer from non-null transactions.
-- Provides the latest point-in-time liquidity metric for customer segmentation.
DROP TABLE IF EXISTS cust_bal_latest;
CREATE TABLE cust_bal_latest (
    customer_id VARCHAR(50) PRIMARY KEY,
    latest_account_balance DECIMAL(15,2)
) AS
SELECT customer_id, balance AS latest_account_balance
FROM (
    SELECT customer_id, balance,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY txn_date DESC, transaction_id DESC) AS rnk
    FROM stage_clean_txns
    WHERE balance IS NOT NULL
) b
WHERE rnk = 1;

-- Step 10: Aggregate transaction counts and identify demographic conflict flags.
-- Flags customers with 2+ valid DOBs or both 'M' and 'F' recorded across transactions.
DROP TABLE IF EXISTS cust_txn_summary;
CREATE TABLE cust_txn_summary (
    customer_id             VARCHAR(50) PRIMARY KEY,
    txn_count               INT NOT NULL,
    profile_conflict_flag   TINYINT NOT NULL
) AS
SELECT 
    customer_id,
    COUNT(*) AS txn_count,
    CASE 
        WHEN COUNT(DISTINCT dob) >= 2 
          OR COUNT(DISTINCT CASE WHEN gender IN ('M', 'F') THEN gender END) >= 2
        THEN 1
        ELSE 0
    END AS profile_conflict_flag
FROM stage_clean_txns
GROUP BY customer_id;

-- Step 11: Create clean master customers dimension table.
-- Consolidates one row per customer with resolved demographics, location, balance, and conflict flag.
DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
    customer_id             VARCHAR(50) PRIMARY KEY,
    gender                  VARCHAR(20) NOT NULL,
    date_of_birth           DATE NULL,
    age                     INT NULL,
    age_group               VARCHAR(20) NOT NULL,
    location_clean          VARCHAR(50) NOT NULL,
    latest_account_balance  DECIMAL(15,2) NULL,
    txn_count               INT NOT NULL DEFAULT 1,
    profile_conflict_flag   TINYINT NOT NULL DEFAULT 0,
    INDEX idx_cust_location (location_clean)
);

-- Step 12: Populate clean customers table by joining resolved attribute tables.
-- Computes standardized age groups: '18-25', '26-35', '36-45', '46-60', '60+', 'Unknown'.
INSERT INTO customers (
    customer_id,
    gender,
    date_of_birth,
    age,
    age_group,
    location_clean,
    latest_account_balance,
    txn_count,
    profile_conflict_flag
)
SELECT 
    cg.customer_id,
    cg.gender,
    cd.dob AS date_of_birth,
    cd.age,
    CASE 
        WHEN cd.age IS NULL THEN 'Unknown'
        WHEN cd.age BETWEEN 18 AND 25 THEN '18-25'
        WHEN cd.age BETWEEN 26 AND 35 THEN '26-35'
        WHEN cd.age BETWEEN 36 AND 45 THEN '36-45'
        WHEN cd.age BETWEEN 46 AND 60 THEN '46-60'
        WHEN cd.age > 60 THEN '60+'
        ELSE 'Unknown'
    END AS age_group,
    cl.location_clean,
    cb.latest_account_balance,
    cts.txn_count,
    cts.profile_conflict_flag
FROM cust_gender_mode cg
JOIN cust_dob_mode cd ON cg.customer_id = cd.customer_id
JOIN cust_loc_mode cl ON cg.customer_id = cl.customer_id
JOIN cust_txn_summary cts ON cg.customer_id = cts.customer_id
LEFT JOIN cust_bal_latest cb ON cg.customer_id = cb.customer_id;

-- Step 13: Clean up intermediate temporary mode tables while preserving stage_clean_txns.
-- stage_clean_txns is kept as a permanent real table so audit queries can be re-run directly.
DROP TABLE IF EXISTS cust_gender_mode;
DROP TABLE IF EXISTS cust_dob_mode;
DROP TABLE IF EXISTS cust_loc_mode;
DROP TABLE IF EXISTS cust_bal_latest;
DROP TABLE IF EXISTS cust_txn_summary;

-- ============================================================================
-- Verification Queries
-- ============================================================================

-- Check total counts of modeled tables
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'transactions' AS table_name, COUNT(*) AS row_count FROM transactions;
