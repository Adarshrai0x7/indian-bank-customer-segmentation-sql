-- Drop old staging table so we can start fresh
DROP TABLE IF EXISTS staging_bank_transactions;

-- Create staging table with text types so raw CSV data loads without errors
CREATE TABLE staging_bank_transactions (
    transaction_id         VARCHAR(50),
    customer_id            VARCHAR(50),
    customer_dob           VARCHAR(50),
    cust_gender            VARCHAR(20),
    cust_location          VARCHAR(255),
    cust_account_balance   VARCHAR(50),
    transaction_date       VARCHAR(50),
    transaction_time       VARCHAR(50),
    transaction_amount     VARCHAR(50)
);

-- Fast bulk load from CSV file into staging table
-- Update the file path below to match your local setup if needed
LOAD DATA LOCAL INFILE 'data/bank_transactions.csv'
INTO TABLE staging_bank_transactions
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES;

-- Check that all 1,048,567 rows were loaded from the CSV file
SELECT COUNT(*) AS staging_row_count
FROM staging_bank_transactions;
