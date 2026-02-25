/*
During this process I discovered a row-count mismatch after unpivoting and 
loading the master CSV into the queue table. At first, it looked like a logic 
or join problem. But testing each step revealed convoluted duplicates, missing 
conflict handling, and an upstream miscount. Once the transformation logic 
checked out, the fix was spoken for and the takeaway as loud as ever:

> Go back to baseline before debugging your data.

This experience introduced me to a more methodical way of approaching data 
validation, lineage tracking, and error isolation within ETL workflows.
*/


-- ####################################################################### --
--                    How are there duplicates?                            --         
-- ####################################################################### --

DROP TABLE IF EXISTS stage_raw; -- Drop raw staging table if it exists (resets query)

-- [EXTRACT]
-- Create a temporary staging table to hold raw CSV data with all columns available for smooth loading
CREATE TEMP TABLE stage_raw (
    date DATE, --- date
    clinicID INT, --- clinicID
    clinicName VARCHAR(255), --- clinicName
    "Hospital and Health Service" VARCHAR(255), --- Hospital and Health Service
    Area TEXT, --- Area
    "Waiting D1" INT,
    "Waiting D2" INT,
    "Waiting D3" INT,
    "Waiting D4" INT,
    "Waiting D5" INT,
    "Waiting D6" INT,
    "Waiting D7" INT,
    "Treated D1" INT,
    "Treated D2" INT,
    "Treated D3" INT,
    "Treated D4" INT,
    "Treated D5" INT,
    "Treated D6" INT,
    "Treated D7" INT
);

-- Load data from CSV into the staging raw table
COPY stage_raw
FROM 'F:/Git/projects/waiting_list/data/processed/master_dataset.csv'
WITH (FORMAT CSV, null "-", HEADER TRUE, DELIMITER ',');


WITH long_tiers AS (
  SELECT date, clinicID AS clinic_id, Area AS visit_type, 'D1' AS period_name, "Waiting D1" AS patients_waiting, "Treated D1" AS patients_treated FROM stage_raw
  UNION ALL
  SELECT date, clinicID, Area, 'D2', "Waiting D2", "Treated D2" FROM stage_raw
  UNION ALL
  SELECT date, clinicID, Area, 'D3', "Waiting D3", "Treated D3" FROM stage_raw
  UNION ALL
  SELECT date, clinicID, Area, 'D4', "Waiting D4", "Treated D4" FROM stage_raw
  UNION ALL
  SELECT date, clinicID, Area, 'D5', "Waiting D5", "Treated D5" FROM stage_raw
  UNION ALL
  SELECT date, clinicID, Area, 'D6', "Waiting D6", "Treated D6" FROM stage_raw
),
period_details AS (
  SELECT 
      wait_period.period_id,
      wait_period.period_name,
      appointment_waitperiod.visit_id,
      appointment.visit_type
  FROM wait_period
  JOIN appointment_waitperiod USING (period_id)
  JOIN appointment USING (visit_id)
),
joined AS ( -- combine long_tier and period_details
  SELECT 
      t.date,
      t.clinic_id,
      d.visit_id,
      d.period_id
  FROM long_tiers t
  JOIN period_details d 
    ON t.visit_type = d.visit_type
   AND t.period_name = d.period_name
)
SELECT -- select and group individual logs, single out logs appearing more than once.
  date, clinic_id, visit_id, period_id, COUNT(*) AS duplicate_count
FROM joined
GROUP BY date, clinic_id, visit_id, period_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC
LIMIT 20;

-- these logs at most have a single duplicate.
-- therefore the 14,175 rows are connected to each log. 
--------------------------------------------------
-- how is a row being duplicated per log?
-- or else the starting csv has a number of duplicates that
-- have been reformated into additional rows via long_tiered
-- 
-- long tiers has unintentional duplicates
-- therefore the master csv could have duplicates

SELECT date, clinic_id, visit_type, period_name, COUNT(*)
FROM long_tiers
GROUP BY date, clinic_id, visit_type, period_name
HAVING COUNT(*) > 1;

/* 
  diagnostics results: checked csv for duplicates in excel.

  2834 duplicate values were found in the original dataset.

  With the current ON CONFLICT condition in place, the data 

  has been cleaned of duplicates upon upload into 'queue'. 
*/


-- ####################################################################### --
--                  Where are the last 5 missing rows?                     --         
-- ####################################################################### --

/*
  Still 5 rows are technically not passing through in
  the loading phase.  

  11,185 * 5 = 55,925

  Load result: 55,920
*/

/* At what point have the 5 rows lost?*/

-- collecting a count of grouped date + clinicID + visit_types
-- amounts to 11,184 groups. With a count of 6 per group
-- one group is missing and the +5 rows tiered

-- we are missing a group down stream, checking master csv
-- and it provides the same output. 

/*
  are there any other suprises from the csv?
  for example - areas that arent specified in the schema,
  nulls appearing in ids, dates etc..
*/

SELECT date, clinic_id, visit_type, period_name, COUNT(*) AS row_count
FROM long_tiers
GROUP BY date, clinic_id, visit_type, period_name
HAVING COUNT(*) > 1
ORDER BY date DESC
LIMIT 20;

SELECT DISTINCT date, clinicID, Area, COUNT(*) AS row_count
FROM stage_raw
GROUP BY date, clinicID, Area
ORDER BY row_count DESC;
-- all areas recorded are as stated

SELECT COUNT(*) AS null_groups
FROM stage_raw
WHERE date IS NULL 
   OR clinicID IS NULL 
   OR Area IS NULL;
-- all select options listed, queried under IS NULL, come back clear.

/*
  can identical combinations be clashing across rows?
  do rows share the same date, clinic_id, period_id, visit_id,
*/

SELECT date, clinic_id, period_id, visit_id
FROM long_tiers


-- ####################################################################### --
--                      Data Debugging Reflection                          --         
-- ####################################################################### --
/*

The review of the data began once the master CSV had been unpivoted and
loaded into the table named `queue`. The aim was to highlight anomalies 
present in the data and diagnose any unexpected outcomes.

Problems appeared in stages as follows:

_  - An unexpected dataframe size  
_  - CSV duplicates  
_  - Mismatch between source data and loaded data  


####################  The Unexpected Data Size

The table as a whole amounted to a number that far exceeded expectations.

That number was: **405,610 rows**

After multiple iterations of updating CSVs and testing code (previously 
without conflict clauses), the row count had been heavily inflated. This 
was confirmed by querying the count of test records (specifically, the year 2023).

**Root Cause:**  
Conflicts were not properly defined when loading the data.  

**Resolution:**  
The `queue` table was truncated and reloaded with an `ON CONFLICT` condition 
in place to prevent duplication on re-runs.  

**Outcome:**  
Because each row was uniquely identified by multiple factors, this conflict 
successfully prevented duplicate entries in future CSV updates.  


####################  The CSV Duplicates

Once the data size was reduced, an expected count was estimated:  
**70,090 rows (14,018 × 5 = 70,090)** — based on the count of rows in the 
master CSV multiplied by the five “long” periods per entry.

Instead, the actual count recorded was **55,920 rows**.  

**Initial Hypothesis:**  
14,170 rows were “missing.” This implied that 2,834 rows may have been 
filtered out upstream in the master CSV. Could tables have been misjoined 
or grouped incorrectly?

**Isolation Steps:**

1. Counted the rows of `long_tiers` to determine if the issue occurred  
   before or after loading to `queue`.  
   -> Result: **84,108 rows**, confirming the discrepancy originated *before* loading.

2. This revealed two key insights:  
   - 84,108 ≠ the anticipated 70,090 -> excess records were being produced.  
   - The load conflict in `queue` was effectively trimming duplicates.  

Upon further review of the master CSV, grouping and counting duplicate visit 
logs (where count > 1) produced **2,834 duplicates** — exactly enough to 
account for the 14,170-row difference after long-format expansion.

**Conclusion:**  
The `ON CONFLICT` clause was functioning as intended, and the final `queue` 
count of **55,920 rows** was correct and validated.


####################  The Phantom Data Discrepancy

At one point, it appeared that five rows were still missing from the total 
even after duplicates were resolved. This led to a deeper re-examination of 
each stage’s counts.

**Findings:**  
The issue was not in the data or SQL logic but rather in a human oversight:  
an incorrect baseline count had been recorded manually.  
The actual `stage_raw` count was **14,018**, not **14,019** as previously logged.

**Outcome:**  
Once corrected, all derived counts aligned perfectly:
11,184 (unique stage_raw) × 5 = 55,920 (expected queue count)

**Lesson Learned:**  
Always verify upstream baselines before debugging downstream transformations.  
This experience reinforced the value of validating assumptions early and 
maintaining clear lineage between raw, normalized, and transformed data.  


####################  Key Takeaways

- Built confidence in systematic debugging and validation workflows.  
- Learned to prioritize verifying input assumptions before suspecting logic errors.  
- Strengthened understanding of conflict handling, normalization, and data lineage.  
- Practiced humility and rigor, these small manual errors can appear as complex issues.

*/