"""
Pipeline Runner for Indian Bank Customer Segmentation (MySQL 8.0)
Reads database credentials from .env and runs the SQL pipeline.
"""

import os
import sys
import time
import mysql.connector
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_PATH = os.path.join(BASE_DIR, "data", "bank_transactions.csv").replace("\\", "/")
ENV_PATH = os.path.join(BASE_DIR, ".env")
SQL_PHASE1 = os.path.join(BASE_DIR, "sql", "01_create_staging.sql")
SQL_PHASE2 = os.path.join(BASE_DIR, "sql", "02_clean_and_model.sql")

# Load environment variables
load_dotenv(ENV_PATH)

def get_connection():
    host = os.getenv("DB_HOST", "localhost")
    port = int(os.getenv("DB_PORT", 3306))
    database = os.getenv("DB_NAME")
    user = os.getenv("DB_USER", "root")
    password = os.getenv("DB_PASSWORD")
    
    conn = mysql.connector.connect(
        host=host,
        port=port,
        database=database,
        user=user,
        password=password,
        allow_local_infile=True
    )
    return conn

def run_phase_1():
    print("=" * 65)
    print("PHASE 1: MYSQL PROJECT SETUP & STAGING LOAD")
    print("=" * 65)
    
    conn = get_connection()
    cursor = conn.cursor()
    
    # 1. Prove MySQL Version
    cursor.execute("SELECT VERSION();")
    version = cursor.fetchone()[0]
    print(f"Connected to MySQL Version: {version}")
    
    cursor.execute("SELECT DATABASE();")
    current_db = cursor.fetchone()[0]
    print(f"Target Database: {current_db}")
    
    # Check local_infile status
    cursor.execute("SHOW VARIABLES LIKE 'local_infile';")
    local_infile_var = cursor.fetchone()
    print(f"MySQL local_infile setting: {local_infile_var[1]}")
    
    # 2. Recreate staging table
    print("\nRecreating staging_bank_transactions table...")
    cursor.execute("DROP TABLE IF EXISTS staging_bank_transactions;")
    cursor.execute("""
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
    """)
    conn.commit()
    print("staging_bank_transactions created successfully.")
    
    # 3. Load CSV via LOAD DATA LOCAL INFILE
    print(f"\nExecuting LOAD DATA LOCAL INFILE from {DATA_PATH}...")
    load_sql = f"""
        LOAD DATA LOCAL INFILE '{DATA_PATH}'
        INTO TABLE staging_bank_transactions
        FIELDS TERMINATED BY ','
        ENCLOSED BY '"'
        LINES TERMINATED BY '\\r\\n'
        IGNORE 1 LINES;
    """
    cursor.execute(load_sql)
    conn.commit()
    print("Data loaded successfully.")
    
    # 4. Audit reconciliation row count
    cursor.execute("SELECT COUNT(*) AS staging_row_count FROM staging_bank_transactions;")
    row_count = cursor.fetchone()[0]
    print(f"\nStaging Row Count: {row_count:,} (Expected: 1,048,567)")
    
    cursor.execute("SELECT * FROM staging_bank_transactions LIMIT 3;")
    sample_rows = cursor.fetchall()
    print("\nSample records:")
    for r in sample_rows:
        print(" ", r)
        
    conn.close()
    return version, row_count

def run_phase_2(skip_execution_if_present=False):
    print("\n" + "=" * 65)
    print("PHASE 2: DATA CLEANING & MODELING (02_clean_and_model.sql)")
    print("=" * 65)
    
    conn = get_connection()
    cursor = conn.cursor()
    
    if not skip_execution_if_present:
        print("\nExecuting sql/02_clean_and_model.sql...")
        with open(SQL_PHASE2, "r", encoding="utf-8") as f:
            sql_content = f.read()
            
        statements = []
        current_stmt = []
        for line in sql_content.splitlines():
            trimmed = line.strip()
            if trimmed.startswith("--") or not trimmed:
                continue
            current_stmt.append(line)
            if trimmed.endswith(";"):
                statements.append("\n".join(current_stmt))
                current_stmt = []
                
        for i, stmt in enumerate(statements, 1):
            t_start = time.time()
            cursor.execute(stmt)
            conn.commit()
            print(f"Step {i:2d}/{len(statements)} executed in {time.time() - t_start:.2f}s")
    else:
        print("\nUsing existing modeled tables in MySQL...")
        
    # Verification & Reconciliations
    print("\n" + "-" * 40)
    print("PHASE 2 AUDIT RECONCILIATION")
    print("-" * 40)
    
    cursor.execute("SELECT COUNT(*) FROM customers;")
    cust_count = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM transactions;")
    txn_count = cursor.fetchone()[0]
    
    print(f"Total Clean Customers:    {cust_count:,} (Expected: 883,660)")
    print(f"Total Clean Transactions: {txn_count:,} (Expected: 1,047,732)")
    
    # Sample Customers
    print("\nSample 5 Customers:")
    cursor.execute("""
        SELECT customer_id, gender, date_of_birth, age, age_group, location_clean, latest_account_balance
        FROM customers
        LIMIT 5;
    """)
    for r in cursor.fetchall():
        print(" ", r)
        
    # Sample Transactions
    print("\nSample 5 Transactions:")
    cursor.execute("""
        SELECT transaction_id, customer_id, transaction_date, transaction_time, transaction_hour, day_of_week, month_label, amount, account_balance
        FROM transactions
        LIMIT 5;
    """)
    for r in cursor.fetchall():
        print(" ", r)
        
    # Hand Verification of Customer C5841053
    print("\nHand Verification - Customer C5841053:")
    cursor.execute("SELECT * FROM staging_bank_transactions WHERE customer_id = 'C5841053';")
    staging_c = cursor.fetchall()
    print(" Staging Record:   ", staging_c[0])
    cursor.execute("SELECT * FROM customers WHERE customer_id = 'C5841053';")
    clean_c = cursor.fetchone()
    print(" Customers Record: ", clean_c)
    
    # 4/4/57 Age Test
    cursor.execute("SELECT TIMESTAMPDIFF(YEAR, '1957-04-04', '2016-10-21');")
    age_test = cursor.fetchone()[0]
    print(f"\n4/4/57 Age Test as of 2016-10-21: {age_test} (Expected: 59)")
    
    conn.close()
    return cust_count, txn_count

def run_phase_3():
    print("\n" + "=" * 65)
    print("PHASE 3: DATA QUALITY & VALIDATION CHECKS (03_validation_checks.sql)")
    print("=" * 65)
    
    conn = get_connection()
    cursor = conn.cursor()
    
    checks = [
        ("Check 1a: Duplicate customer_id in customers", """
            SELECT customer_id, COUNT(*) AS duplicate_count
            FROM customers
            GROUP BY customer_id
            HAVING COUNT(*) > 1;
        """),
        ("Check 1b: Duplicate transaction_id in transactions", """
            SELECT transaction_id, COUNT(*) AS duplicate_count
            FROM transactions
            GROUP BY transaction_id
            HAVING COUNT(*) > 1;
        """),
        ("Check 2: Orphan transactions (missing from customers)", """
            SELECT t.transaction_id, t.customer_id
            FROM transactions t
            LEFT JOIN customers c ON t.customer_id = c.customer_id
            WHERE c.customer_id IS NULL;
        """),
        ("Check 3: Transactions outside 2016-08-01 to 2016-10-21", """
            SELECT transaction_id, transaction_date
            FROM transactions
            WHERE transaction_date < '2016-08-01' OR transaction_date > '2016-10-21';
        """),
        ("Check 4: Customer ages outside 18-100", """
            SELECT customer_id, age
            FROM customers
            WHERE age IS NOT NULL AND (age < 18 OR age > 100);
        """),
        ("Check 5: Row count reconciliation (clean + zero != 1,048,567)", """
            SELECT clean_count, zero_count, (clean_count + zero_count) AS total_count, staging_count
            FROM (
                SELECT 
                    (SELECT COUNT(*) FROM transactions) AS clean_count,
                    (SELECT COUNT(*) FROM staging_bank_transactions WHERE CAST(TRIM(transaction_amount) AS DECIMAL(15,2)) = 0) AS zero_count,
                    (SELECT COUNT(*) FROM staging_bank_transactions) AS staging_count
            ) counts
            WHERE (clean_count + zero_count) != staging_count OR staging_count != 1048567;
        """),
        ("Check 6: Customer latest balance vs latest txn balance mismatch", """
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
        """),
        ("Check 6b: NULL latest balance with non-null transaction balance", """
            SELECT c.customer_id
            FROM customers c
            JOIN transactions t ON c.customer_id = t.customer_id AND t.account_balance IS NOT NULL
            WHERE c.latest_account_balance IS NULL;
        """),
        ("Check 7: Customer age matches DOB as of 2016-10-21", """
            SELECT customer_id, date_of_birth, age, TIMESTAMPDIFF(YEAR, date_of_birth, '2016-10-21') AS expected_age
            FROM customers
            WHERE date_of_birth IS NOT NULL 
              AND age != TIMESTAMPDIFF(YEAR, date_of_birth, '2016-10-21');
        """),
        ("Check 8: Customer gender is strictly M, F, or Unknown", """
            SELECT customer_id, gender
            FROM customers
            WHERE gender NOT IN ('M', 'F', 'Unknown') OR gender IS NULL;
        """)
    ]
    
    all_passed = True
    for name, sql in checks:
        t_start = time.time()
        cursor.execute(sql)
        rows = cursor.fetchall()
        elapsed = time.time() - t_start
        status = "PASSED (0 rows)" if len(rows) == 0 else f"FAILED ({len(rows)} rows)"
        print(f"  {name:60s} -> {status} [{elapsed:.2f}s]")
        if len(rows) > 0:
            all_passed = False
            for r in rows[:3]:
                print(f"     Failed row: {r}")
                
    conn.close()
    if all_passed:
        print("\nALL PHASE 3 VALIDATION CHECKS PASSED: 0 anomalous rows detected across all checks.")
    else:
        print("\nPHASE 3 VALIDATION FAILED: Anomalies detected.")
    return all_passed

def run_phase_4():
    print("=" * 65)
    print("PHASE 4: CUSTOMER FEATURE ENGINEERING & VERIFICATION")
    print("=" * 65)
    
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    
    # 1. Check customer_features table
    cursor.execute("SELECT COUNT(*) AS cnt FROM customer_features;")
    feat_count = cursor.fetchone()["cnt"]
    print(f"customer_features table contains: {feat_count:,} rows (Expected: 883,660)")
    
    # 2. Spend distribution
    cursor.execute("""
        SELECT 
            MIN(total_spend) AS min_spend,
            MAX(total_spend) AS max_spend,
            ROUND(AVG(total_spend), 2) AS avg_spend,
            ROUND(SUM(total_spend), 2) AS total_market_spend,
            COUNT(*) AS total_customers
        FROM customer_features;
    """)
    spend_summary = cursor.fetchone()
    print("\nTotal Spend Distribution:")
    for k, v in spend_summary.items():
        print(f"  {k}: {v}")
        
    # 3. Top 5 customers
    cursor.execute("""
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
    """)
    top5 = cursor.fetchall()
    print("\nTop 5 Customers by Total Spend:")
    for r in top5:
        print(f"  Cust {r['customer_id']}: Spend={r['total_spend']}, Txns={r['txn_count']}, Flag={r['profile_conflict_flag']}, LatestBal={r['latest_balance']}")
        
    cursor.close()
    conn.close()
    print("\nPHASE 4 COMPLETED SUCCESSFULLY.")
    return True

def run_phase_5():
    print("=" * 65)
    print("PHASE 5: VALUE & RFM SEGMENTATION")
    print("=" * 65)
    
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    
    cursor.execute("SELECT COUNT(*) AS cnt FROM customer_segments;")
    seg_cnt = cursor.fetchone()["cnt"]
    print(f"customer_segments table contains: {seg_cnt:,} rows (Expected: 883,660)")
    
    cursor.execute("""
        SELECT 
            value_segment,
            COUNT(*) AS customers,
            ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_segments), 2) AS pct_customers,
            ROUND(SUM(total_spend) * 100.0 / (SELECT SUM(total_spend) FROM customer_segments), 2) AS pct_total_spend
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
    """)
    val_rows = cursor.fetchall()
    print("\nValue Segments Breakdown:")
    for r in val_rows:
        print(f"  {r['value_segment']:18s}: {r['customers']:,} ({r['pct_customers']}%), Spend Share: {r['pct_total_spend']}%")
        
    cursor.execute("""
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
                WHEN 'Big One-time Spenders' THEN 3
                WHEN 'Recent Light' THEN 4
                WHEN 'Inactive since August' THEN 5
                WHEN 'Others' THEN 6
            END;
    """)
    rfm_rows = cursor.fetchall()
    print("\nRFM Segments Breakdown:")
    for r in rfm_rows:
        print(f"  {r['rfm_segment']:30s}: {r['customers']:,} ({r['pct_customers']}%), Spend Share: {r['pct_total_spend']}%")
        
    cursor.close()
    conn.close()
    print("\nPHASE 5 COMPLETED SUCCESSFULLY.")
    return True

def run_phase_6():
    print("=" * 65)
    print("PHASE 6: BUSINESS QUESTIONS & INSIGHTS")
    print("=" * 65)
    
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Q1
    cursor.execute("""
        WITH ranked_customers AS (
            SELECT total_spend, NTILE(10) OVER (ORDER BY total_spend DESC) AS spend_decile
            FROM customer_features
        )
        SELECT 
            COUNT(*) AS top_10pct_customers,
            ROUND(SUM(total_spend), 2) AS top_10pct_spend,
            ROUND(SUM(total_spend) * 100.0 / (SELECT SUM(total_spend) FROM customer_features), 2) AS pct_total_spend
        FROM ranked_customers
        WHERE spend_decile = 1;
    """)
    q1 = cursor.fetchone()
    print(f"\nQ1 (Top 10% Spenders): {q1['top_10pct_customers']:,} customers generate {q1['pct_total_spend']}% of total spend.")
    
    # Q4
    cursor.execute("""
        SELECT 
            COUNT(*) AS august_only_customers,
            ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_features), 2) AS pct_customers,
            ROUND(SUM(latest_balance), 2) AS total_latest_balance
        FROM customer_features
        WHERE last_txn_date <= '2016-08-31';
    """)
    q4 = cursor.fetchone()
    print(f"Q4 (August Only Inactive): {q4['august_only_customers']:,} ({q4['pct_customers']}%) customers hold ₹{q4['total_latest_balance']:,} in deposits.")
    
    # Q6
    cursor.execute("""
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
        SELECT * FROM monthly_metrics ORDER BY txn_month;
    """)
    print("\nQ6 (Monthly Active Day Comparison):")
    for r in cursor.fetchall():
        note = " [partial: 2 days of data]" if r['txn_month'] == '2016-10' else ""
        print(f"  {r['txn_month']}: {r['active_dates']} active dates | {r['total_txns']:,} txns | Avg {r['avg_txns_per_active_date']:,} txns/day | ₹{r['avg_value_per_active_date']:,}/day{note}")
        
    cursor.close()
    conn.close()
    print("\nPHASE 6 COMPLETED SUCCESSFULLY.")
    return True

if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "all"
    
    if action in ("phase1", "all"):
        v, c = run_phase_1()
    if action in ("phase2", "all"):
        cust_c, txn_c = run_phase_2(skip_execution_if_present=True)
    if action in ("phase3", "all"):
        passed = run_phase_3()
    if action in ("phase4", "all"):
        run_phase_4()
    if action in ("phase5", "all"):
        run_phase_5()
    if action in ("phase6", "all"):
        run_phase_6()

