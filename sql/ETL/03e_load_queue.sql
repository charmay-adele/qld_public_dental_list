-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
-- Truncate the table before loading new data
TRUNCATE TABLE queue RESTART IDENTITY;

-- Unique Index must be created before CTEs
CREATE UNIQUE INDEX IF NOT EXISTS idx_q_ymd_ids ON queue (date, clinic_id, period_id, visit_id);

WITH long_tiers AS (
  SELECT date, clinicID AS clinic_id, Area AS visit_type, 'D1' AS period_name, "Waiting D1" AS patients_waiting, "Treated D1" AS patients_treated
  FROM stage_raw
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
    wait_period.period_description,
    appointment_waitperiod.visit_id,
    appointment.visit_type
FROM wait_period
JOIN appointment_waitperiod ON appointment_waitperiod.period_id = wait_period.period_id
JOIN appointment ON appointment.visit_id = appointment_waitperiod.visit_id
)

INSERT INTO queue (date, clinic_id, visit_id, period_id, patients_waiting, patients_treated)
SELECT t.date, t.clinic_id, d.visit_id, d.period_id, t.patients_waiting, t.patients_treated
FROM long_tiers t
JOIN period_details d ON (t.visit_type = d.visit_type
AND t.period_name = d.period_name)
ON CONFLICT (date, clinic_id, period_id, visit_id) DO NOTHING;

DO $$
BEGIN
RAISE NOTICE 'Inserted % rows into queue', (SELECT COUNT(*) FROM queue);
END $$;

SELECT *
FROM queue
LIMIT 10;


/* Code with Notation */
-- -- -- -- Run if master CSV is updated.
-- Truncate the table before loading new data
TRUNCATE TABLE queue RESTART IDENTITY;
-- Unique Index must be created before CTEs
CREATE UNIQUE INDEX IF NOT EXISTS idx_q_ymd_ids ON queue (date, clinic_id, period_id, visit_id);

-- {{ QUEUE }} --

-- The Queue table stores the most granular data. Featuring logs of waiting and treated patients.

--         Schema: 
--         log_id, date, clinic_id, visit_id, period_id, patients_waiting, patients_treated

-- In order to populate this table, we must:

-- == Step One == -- Normalise Data ( Wide > Long )
  -- Create CTE: long_tiers
  -- Purpose: Normalise raw data from wide format to long format for easier analysis.

  -- The goal is to reshape the master 'stage_raw' dataset, which currently stores
  -- multiple period columns (D1, D2, D3...) in a wide format, into a standardised
  -- long format where each row represents one period observation.

    -- Approach:
    --   • Use a CTE to select relevant fields from temp master dataset 'stage_raw':
    --       - date
    --       - clinicID (renamed to clinic_id)
    --       - Area (mapped to visit_type)
    --   • Create a new column 'period_name' to label the data tier (e.g., 'D1', 'D2').
    --   • Map source columns:
    --       - "Waiting D#" → patients_waiting  
    --       - "Treated D#" → patients_treated
    --   • Use UNION ALL to append all tier subsets into one long table.

WITH long_tiers AS (
  SELECT date, clinicID AS clinic_id, Area AS visit_type, 'D1' AS period_name, "Waiting D1" AS patients_waiting, "Treated D1" AS patients_treated
  FROM stage_raw
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
  
-- SELECT COUNT(*) FROM long_tiers; -- Should be 8 times the number of rows in stage_raw, as there are 8 tiers (D1-D7 + D6)
  
-- == Step Two == -- Shape frame of Reference

  -- Create CTE: period_details
  -- Purpose: Add queue characteristics linked to each period_id.

  -- The goal is to build a CTE that associates key wait period details 
  -- (name, description) with corresponding appointment attributes (visit_type),
  -- allowing each queue row to reference the correct period_id.

    -- Approach:
    --   • The 'long_tier' table contains both appointment (visit_type) 
    --     and wait period (period_name) characteristics.  
    --   • We use these shared features to align queue data with 
    --     the correct wait period definitions.  
    --   • This CTE joins:
    --       - 'appointment_waitperiod' (junction table),
    --       - 'appointment', and
    --       - 'wait_period',
    --     bridging the relationship between visit_type and period_id 
    --     for accurate insertion and assignment of queue data.

period_details AS (
SELECT 
    wait_period.period_id,
    wait_period.period_name,
    wait_period.period_description,
    appointment_waitperiod.visit_id,
    appointment.visit_type
FROM wait_period
JOIN appointment_waitperiod ON appointment_waitperiod.period_id = wait_period.period_id
JOIN appointment ON appointment.visit_id = appointment_waitperiod.visit_id
)
  
-- == Step three == -- Insert Joined Data into Queue

  -- Insert data into Queue's specified columns 

    -- to do this: use above CTEs and tables to map new table format
      --          - insert into Queue - transplanting CTE values into Queue
      --          - from CTE tiered_with_row (t) 
      --                      - join appointment (a) by visit_type/area 
      --                      - join CTE appointment_periods (ap) by a.visit_id and by ap.period_ordinal/t.tier_ordinal 
      --            this attaches all appointment's info by area, allowing visit_id to map appointment_period row numbers

/*
  In order to INSERT without duplicating log entries
  Index together unique identifiers for each line - eg. date, clinic_name, visit_id, period_id
  https://stackoverflow.com/questions/35888012/use-multiple-conflict-target-in-on-conflict-clause

  then outline ON CONFLICT ..Index.. DO NOTHING
  https://www.postgresql.org/docs/current/sql-insert.html#:~:text=ON%20CONFLICT%20DO%20NOTHING%20simply,insertion%20as%20its%20alternative%20action.

*/

/*
What ways are there to specify dupe behaviour

  option 1: index + on conflict
  CREATE UNIQUE INDEX col_1_2_3 ON queue (col1, col2, col3)
  ON CONFLICT (col1, col2, col3) DO whatever

  option 2: alter + constraint + on conflict 
  ALTER TABLE queue
  ADD CONSTRAINT unique_q UNIQUE (col1, col2, col3)
  ON CONFLICT ON CONSTRAINT unique_q DO whatever

  option 3: Exclusion, no two rows have overlapping/conflicting values
  ALTER TABLE queue
  ADD CONSTRAINT q_no_overlap
  EXCLUDE USING gist (
    clinic_id WITH =,
    period_id WITH =,
    date WITH &&
  ); No two rows may have the same clinic and period if their date values overlap &&

This scenario option 1 is used to prevent duplicates entries 
for dates+clinics+periods+visits     
INDEX does not alter the table schema, and simply performs the task.
Keep TRUNCATE to this loading file as it is operational transformation
*/

-- Insert data with conflict handling
-- Mapping:
--   queue.date             <- t.date (from long_tiers)
--   queue.clinic_id        <- t.clinic_id (from long_tiers)
--   queue.visit_id         <- d.visit_id (from period_details)
--   queue.period_id        <- d.period_id (from period_details)
--   queue.patients_waiting <- t.patients_waiting (from long_tiers)
--   queue.patients_treated <- t.patients_treated (from long_tiers)

INSERT INTO queue (date, clinic_id, visit_id, period_id, patients_waiting, patients_treated)
SELECT t.date, t.clinic_id, d.visit_id, d.period_id, t.patients_waiting, t.patients_treated
FROM long_tiers t
JOIN period_details d ON (t.visit_type = d.visit_type
AND t.period_name = d.period_name)
ON CONFLICT (date, clinic_id, period_id, visit_id) DO NOTHING;

DO $$
BEGIN
RAISE NOTICE 'Inserted % rows into queue', (SELECT COUNT(*) FROM queue);
END $$;
/* Do not use SELECT * ... keep analysis replicable
*//* https://stackoverflow.com/questions/321299/what-is-the-reason-not-to-use-select*/

SELECT *
FROM queue
LIMIT 10;