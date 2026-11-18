"""
Ingestion script: Load raw Synthea CSV files into DuckDB raw schema.
Deterministic and idempotent: rerunning replaces the tables cleanly.
"""

import os
import glob
import duckdb

DB_PATH = "warehouse.duckdb"
RAW_DIR = "data/raw"

def load_raw_data():
    print(f"Connecting to DuckDB database at '{DB_PATH}'...")
    con = duckdb.connect(DB_PATH)

    print("Creating 'raw' schema if not exists...")
    con.execute("CREATE SCHEMA IF NOT EXISTS raw;")

    csv_files = glob.glob(os.path.join(RAW_DIR, "*.csv"))
    if not csv_files:
        raise FileNotFoundError(f"No CSV files found in {RAW_DIR}")

    print(f"Found {len(csv_files)} CSV files to ingest into 'raw' schema.")

    for filepath in sorted(csv_files):
        table_name = os.path.splitext(os.path.basename(filepath))[0].lower()
        print(f"Loading '{filepath}' -> raw.{table_name}...")
        
        # Load one-to-one into raw schema using DuckDB's optimized CSV reader
        # all_varchar=false lets DuckDB auto-detect reasonable primitives while keeping exact raw column names
        load_sql = f"""
            CREATE OR REPLACE TABLE raw.{table_name} AS 
            SELECT * FROM read_csv('{filepath}', header=true, all_varchar=true);
        """
        con.execute(load_sql)
        
        count = con.execute(f"SELECT COUNT(*) FROM raw.{table_name}").fetchone()[0]
        print(f"  Loaded {count:,} rows into raw.{table_name}")

    print("\nVerifying loaded tables in raw schema:")
    tables = con.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'raw' 
        ORDER BY table_name;
    """).fetchall()

    for (t,) in tables:
        cnt = con.execute(f"SELECT COUNT(*) FROM raw.{t}").fetchone()[0]
        cols = [c[0] for c in con.execute(f"PRAGMA table_info('raw.{t}')").fetchall()]
        print(f"  - raw.{t}: {cnt:,} rows, {len(cols)} columns")

    con.close()
    print("\nRaw load complete.")

if __name__ == "__main__":
    load_raw_data()
