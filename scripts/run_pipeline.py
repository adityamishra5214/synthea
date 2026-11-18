"""
End-to-End Orchestration Script:
1. Ingests raw Synthea CSV data into DuckDB raw schema.
2. Runs dbt models across staging, intermediate, and marts layers.
3. Executes automated data quality tests.
4. Outputs computed clinical outcome summaries.
"""

import os
import sys

# Ensure project root is in sys.path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import duckdb
from dbt.cli.main import dbtRunner
from scripts.load_raw import load_raw_data

def run_dbt_command(cli_args):
    print(f"\n[dbt] Running: dbt {' '.join(cli_args)}...")
    res = dbtRunner().invoke(cli_args + ["--profiles-dir", "."])
    if not res.success:
        print(f"[ERROR] dbt command failed: {' '.join(cli_args)}")
        sys.exit(1)
    print(f"[OK] dbt {' '.join(cli_args)} completed successfully.")

def print_summary():
    print("\n" + "=" * 70)
    print("CLINICAL OUTCOME MARTS SUMMARY FINDINGS")
    print("=" * 70)

    con = duckdb.connect("warehouse.duckdb")

    # 1. 30-Day Readmissions
    print("\n--- 1. Inpatient 30-Day Readmissions (mart_readmission_30d) ---")
    readmit_summary = con.execute("""
        SELECT 
            COUNT(*) AS total_index_admissions,
            SUM(readmit_flag) AS total_readmissions_30d,
            ROUND(AVG(readmit_flag) * 100.0, 2) AS readmit_rate_pct,
            ROUND(AVG(CASE WHEN readmit_flag = 1 THEN days_to_readmit END), 1) AS avg_days_to_readmission
        FROM analytics_marts.mart_readmission_30d
    """).fetchone()
    print(f"Total Index Inpatient Admissions : {readmit_summary[0]:,}")
    print(f"Total 30-Day Readmissions         : {readmit_summary[1]:,}")
    print(f"Overall 30-Day Readmission Rate   : {readmit_summary[2]}%")
    print(f"Avg Days to Readmit (when flagged): {readmit_summary[3]} days")

    print("\nTop Inpatient Readmission Conditions:")
    top_readmit = con.execute("""
        SELECT 
            primary_condition,
            COUNT(*) AS index_admissions,
            SUM(readmit_flag) AS readmissions_30d,
            ROUND(AVG(readmit_flag) * 100.0, 1) AS readmission_rate_pct
        FROM analytics_marts.mart_readmission_30d
        GROUP BY primary_condition
        HAVING COUNT(*) >= 10
        ORDER BY readmissions_30d DESC
        LIMIT 3
    """).fetchall()
    for row in top_readmit:
        print(f"  * {row[0]}: {row[2]}/{row[1]} readmitted ({row[3]}%)")

    # 2. Comorbidity Pairs
    print("\n--- 2. High-Frequency Comorbidities in 60+ Cohort (mart_comorbidity_pairs) ---")
    top_pairs = con.execute("""
        SELECT 
            condition_a,
            condition_b,
            patient_count,
            total_cohort_patients,
            pct_of_cohort,
            rank_in_cohort
        FROM analytics_marts.mart_comorbidity_pairs
        WHERE cohort = '60+ Elderly'
        ORDER BY rank_in_cohort ASC
        LIMIT 3
    """).fetchall()
    for row in top_pairs:
        print(f"  #{row[5]} [{row[4]}% cohort prevalence - {row[2]}/{row[3]} patients]:")
        print(f"     Condition A: {row[0]}")
        print(f"     Condition B: {row[1]}")

    # 3. Chronic Medication Adherence
    print("\n--- 3. Chronic Disease Medication Adherence (mart_chronic_adherence) ---")
    adherence_summary = con.execute("""
        SELECT 
            condition,
            COUNT(*) AS total_patients,
            ROUND(AVG(adherence_proxy) * 100.0, 1) AS avg_adherence_proxy_pct,
            SUM(active_med_flag) AS active_on_meds,
            ROUND(AVG(gap_days), 1) AS avg_gap_days,
            ROUND(SUM(CASE WHEN adherence_category = 'High Adherence (>=80%)' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS pct_high_adherence
        FROM analytics_marts.mart_chronic_adherence
        GROUP BY condition
        ORDER BY condition
    """).fetchall()
    for row in adherence_summary:
        print(f"  * {row[0]} (N = {row[1]}):")
        print(f"     Avg Adherence Proxy: {row[2]}% | High Adherence Rate (>=80% coverage): {row[5]}%")
        print(f"     Active on Therapy: {row[3]}/{row[1]} | Avg Therapy Gap: {row[4]} days")

    con.close()
    print("\n" + "=" * 70)
    print("PIPELINE EXECUTION & VERIFICATION COMPLETE")
    print("=" * 70)

if __name__ == "__main__":
    print("Starting pipeline execution...")
    load_raw_data()
    run_dbt_command(["run"])
    run_dbt_command(["test"])
    print_summary()
