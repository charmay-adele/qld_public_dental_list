
-- ETL WORKING OUT PROCESS FOR QUEUE TABLE POPULATION
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


  -- {{ QUEUE }} --

  -- The Queue table stores the most granular data. Featuring logs of waiting and treated patients.

  --         Schema: 
  --         log_id, date, clinic_id, visit_id, period_id, patients_waiting, patients_treated

  -- In order to populate this table, we must:

  -- == Step one == -- Normalise Data ( Wide > Long )

    -- Reframe the master stage_raw data from a wide format (columns D1,D2,D3..) in a long format (rows).

    -- to do this: Use CTE to select columns, map tiers, and patient types. UNION ALL rows.
        --        
        --          - create CTE 'long_tiers' which selects 
        --                         - date, clinicID and Area from stage_raw (master)
        --                         - creates column 'tier' with the value 'D1' (or specified value)
        --                         - Map: (to new field name) 
        --                            - "Waiting D1" column to patients_waiting
        --                            - "Treated D1" column to patients_treated
        --                       
        --          - union all to append rows from these selected columns, populating the table length/long ways.
        --                         - apply to following columns, eg.'Waiting D2'..'D3','D4'

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
  )

  /* SELECT date, clinic_id, visit_type, COUNT(*)
  FROM long_tiers
  GROUP BY date, clinic_id, visit_type
  ORDER BY count DESC; */
    
  SELECT COUNT(*)
  FROM long_tiers;
  -- == Step two == -- Add Row Numbers

    -- Assign numbers to rows of specified groups 

      -- to do this: group fields/properties into CTEs and assign identifying numbers. 
        --          - create CTE 'tiered_with_row' which selects long_tiers and assigns each row a number, 
        --            according to each collective date,clinicID, Area - ordered by tier. (eg.D1)
        --          - create CTE 'appointment_period' assigns each row a number from appointment_waitperiod (table previously created)
        --            partitioned by appointment visit_id(eg. 10) and ordered by wait time period_id (eg.101).
    
        --          - Now we have row numbers assigned for both the order of tiers "tier_ordinal" of each date+clinicID+area,
        --             and each type of appointment+waitperiod "period_ordinal"

        --                         - eg. tier_ordinal no.01 = date:04/25, clinicID:1, area:"Clinical Assessment"
        --                         - eg. period_ordinal no.01 = visit_id:10, period_id:101




  period_details AS (
  SELECT 
      wait_period.period_id,
      wait_period.period_name,
      wait_period.period_description,
      appointment_waitperiod.visit_id,
      appointment.visit_type
  FROM wait_period
  JOIN appointment_waitperiod ON appointment_waitperiod.period_id = wait_period.period_id
  JOIN appointment ON appointment.visit_id = appointment_waitperiod.visit_id)

  SELECT t.date, t.clinic_id, d.period_id, d.visit_id, t.patients_waiting, t.patients_treated
  FROM long_tiers t
  JOIN period_details d ON (t.visit_type = d.visit_type
  AND t.period_name = d.period_name)


-- EDA ON WAITING LIST TIER VOLUMES OVER TIME
  /*
  'Clinical Assessment' Quarterly Data Example:
  */QTR |  Year  | Period_Tier |  Timeline  | Is_Desired | Waiting | Treated/*
  ----------------------------------------------------------------------------
      1  	 2020	    D1	       0–1 month     True	       480     765
      1	 2020	    D2	       1–2 months    False	        96	  1743
      1	 2020	    D3	       2–3 months    False	        15	   363
      1	 2020	    D4	       3–4 months    False	         3	    75
      1	 2020	    D5	       4–5 months    False	         9	    24
  */

  /*
  'Clinical Assessment' Quarterly Data Example:
  */QTR |  Year  | Period_Tier |  Timeline  | Is_Desired | Waiting | Treated/*
  ----------------------------------------------------------------------------
      3  	 2020	    D5	       4–5 months    False	        78     129
      4	 2020	    D5	       4–5 months    False	        15      18
  /*

  -- If Q3 2020 had 79 total waiting and 129 treated patients
  -- and Q4 2020 had 15 total waiting and 18 treated patients
  -- Does that mean the waiting list reduced by 64 patients (79 - 15) while only 18 were treated?
  /*
      What happened to the missing 64 D5 Patients from Q3 to Q4 2020?
      -- Possible explanations:
      1. Some patients may have been removed from the waiting list for various reasons 
      (e.g., they sought treatment elsewhere, their condition improved, or they were no longer eligible for treatment).
      2. New patients may have been added to the waiting list in Q4 2020, offsetting the reduction from those treated or removed.
      3. Data reporting inconsistencies or delays could also affect the numbers.
  */
  -- We need to explore the pattern of patient migration across tiers of wait times to understand this better.
  /*  
      To do this, we can track the number of patients in each wait time tier across quarters.
      This will help us see if patients are moving from longer wait times to shorter ones, 
      or if they are being removed from the list for other reasons.*/
  */
  -- Stock and Flow Measurement of Patients Waiting and Treated Over Time
  /*  
      The flux of patients waiting in each tier over time,
      alongside the number of patients treated, to see how these numbers interact.
  */
  Waiting = Snapshot count at quarter-end
  Treated = Flow of patients treated during the quarter
  Ending Waitlist = Starting Waitlist + New Arrivals - Treated Patients - Removed Patients
  Removals include: patients aging into longer wait time tiers, or removing themselves from the list completely. 

  When patients are moving from tier to tier, and those tiers are growing a shrinkling over time

/*  
      Migration of patients across tiers would be key to understanding the dynamics of the waiting list.
      Supporting our question of "How effectively are Queensland public dental clinics managing patient 
      demand across services and catchments?". However the neccessary data to track individual patient 
      movements across tiers is not available in the current dataset. Without knowing a tier's new 
      patients and removed patients, we can only observe aggregate numbers per tier per quarter. 
*/

-- Waiting trends across different service areas (e.g., general vs. priority treatment)?
        -- example previous 2 years
        /*
        quarter	year	visit	    total_waiting	total_treated	pct_change_waiting
        3	    2023	General	    119,700	        14,907	        -65.63%
        4	    2023	General	    125,064	        11,162	          4.48%
        1	    2024	General	    126,987	        14,357	          1.54%
        2	    2024	General	    130,940	        13,246	          3.11%
        3	    2024	General	    131,624	        17,823	          0.52%
        4	    2024	General	    136,236	        12,426	          3.50%
        1	    2025	General	    140,165	        12,726	          2.88%
        2	    2025	General	    147,712	        11,475	          5.38%
        */
        -- Quarterly Totals of Patients Waiting vs Treated by Appointment Type and rate of inflow
        -- CTE with dim_date join to queue and appointment to get totals per quarter/year/visit type
        WITH quarter_totals AS (
            SELECT 
                quarter, 
                year, 
                appointment.visit_type AS visit, 
                    SUM(queue.patients_waiting) AS total_waiting, 
                    SUM(queue.patients_treated) AS total_treated
            FROM dim_date
            LEFT JOIN queue ON dim_date.date = queue.date
            LEFT JOIN appointment ON queue.visit_id = appointment.visit_id
            GROUP BY quarter, year, visit
            ),
        -- CTE crossjoin to get all combinations of quarter/year and visit types
        -- Generate all possible quarter/year and visit_type combinations for completeness in later joins
        all_combinations AS (
            SELECT DISTINCT
                d.quarter, 
                d.year, 
                v.visit_type AS visit
            FROM (
                SELECT DISTINCT quarter, year FROM dim_date) AS d
            CROSS JOIN (
                SELECT DISTINCT visit_type FROM appointment) AS v
        )

        /*-- CTE inspection; Each visit_type has 4 quarters for each year from 2020 to 2025
            SELECT quarter, year, visit_type
            FROM all_combinations
            ORDER BY visit_type, year, quarter
            LIMIT 20;*/
    
    -- Left join quarter_totals to all_combinations to fill in missing combinations with NULLs
        SELECT 
        ac.quarter, ac.year, ac.visit, qt.total_waiting, qt.total_treated,
        CASE WHEN LAG(qt.total_waiting) OVER (
                PARTITION BY ac.visit
                ORDER BY qt.year, qt.quarter
                ) IS NULL THEN NULL
            ELSE CONCAT(ROUND(
            (qt.total_waiting - LAG(qt.total_waiting) OVER (PARTITION BY ac.visit ORDER BY ac.year, ac.quarter))::NUMERIC
            / LAG(qt.total_waiting) OVER (PARTITION BY ac.visit ORDER BY ac.year, ac.quarter) * 100, 2), '%')
    END AS pct_change_waiting
        FROM all_combinations ac
        LEFT JOIN quarter_totals qt ON qt.quarter = ac.quarter 
            AND qt.year = ac.year 
            AND qt.visit = ac.visit
        ORDER BY ac.visit, ac.year, ac.quarter;



SELECT c.clinic_name, a.visit_type, wp.period_name, wp.period_description, 
        EXTRACT(QUARTER FROM q.date) AS quarter, 
        EXTRACT(YEAR FROM q.date) AS year,
        SUM(q.patients_waiting) AS patients_waiting,
        em.excess_wait,
        ROUND(SUM(q.patients_waiting) * em.excess_wait, 2) AS weighted_excess_wait,
        ROUND(SUM(q.patients_treated), 2) AS patients_treated
        -- what proportion of patients taking a particular visit_type?
        FROM queue q
        JOIN clinic c ON c.clinic_id = q.clinic_id
        JOIN appointment a ON a.visit_id = q.visit_id
        JOIN appointment_waitperiod aw ON a.visit_id = aw.visit_id
        JOIN wait_period wp ON wp.period_id = aw.period_id
        JOIN excess_metric em ON a.visit_type = em.visit_type
        GROUP BY c.clinic_name, a.visit_type, wp.period_name, wp.period_description, quarter, year, em.excess_wait
        ORDER BY c.clinic_name, a.visit_type, year DESC;
        -- Note: this query currently isn't dividing patients_waiting by wait period tiers, 
        -- there are multiple tiers per visit type. However the patients waiting are duplicated across tiers.
        -- we need the patients to be portioned by tier. 

*/

SELECT *
FROM queue;
