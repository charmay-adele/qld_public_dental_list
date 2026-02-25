
Database tables are pre-populated; no CSV load is required to start analysis.

If you wish to recreate the database from scratch:
## Load the Data

With the following steps, populate the staging table with the CSV data.

1. Open a terminal.
2. Navigate to the project root:

```bash
cd ~/Portfolio/qld_public_dental_list
psql -d postgres -f sql/ETL/03_load_data.sql
```

