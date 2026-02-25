
-- -- Schema -- --
-- clinic                 | **clinic_id**, *clinic_name*, catchment }
-- appointment            | { **visit_id**, visit_type, schedule }
-- wait_period            | { **period_id**, period_name, period_tier, period_description, start_month, end_month, is_desired }
-- appointment_waitperiod | { **visit_id**, **period_id** } |
-- queue                  | { **log_id**, date, **period_id**, **clinic_id**, patients_waiting, patients_treated }


-- -- To Review -- --
-- Search for dirty data, ensure entries are accurate, consistent and complete.
-- Get a look at the general landscape, explore defining features of the dataset

-- The original master csv has ~14,000 rows
-- how many rows are there now the data has been normalised? 405,610 rows

/* SELECT COUNT(*) as total_rows
FROM queue q */

/*
    After processing wide to long, 2 columns are redistributed into to 6 rows.
    therefore 5 x rows added to a given entry

    5 * 14,019 = 70,095 rows

    Why are there so many?

    - I executed the data loading twice when I updated the master csv. Could there be duplicates?
    - Have I normalised/split up rows beyond patients waiting and treated? 

*/

/* 
    lets have a look at the ids, the ids won't be duplicates as those are generated
    however, we can check the dates - as the tested data loaded before the major upload
    were from dates around year 2023
*/

/* SELECT date, log_id, patients_waiting
FROM queue
WHERE date > '2023-01-01' */

/*
    it appears no duplicates are occuring in patients_waiting,
    but they could be loaded in chunks and not meshed/shuffled.
    Even so, if these duplicates are result of a previous load..
    it was only 2 years max worth of data - would not offset the 
    row count that dramatically. 

    let's check if any unique looking patient_waiting are duplicated
*/


/* SELECT date, clinic_id, period_id, visit_id, patients_waiting
FROM queue
WHERE date > '2023-01-01' */

/*
    for the same date there are 11 occurances of the same period_name "D1" 
    and clinic_name "Kawana Dental Clinic" for the same number of patients
    waiting. Where patient_waiting = 1759 

    Where patient_waiting = 1015, period_names D4 + D3 appears 10 times with the same 
    patients waiting on the same date, and D2 appears once. 
*/

/* 
    Conclusion? all the times I have tested and loaded data into the queue
    table has not followed the intended updatability - I should have outlined conflicts.

    Queue table is a candidate for TRUNCATE as it is a child table (with no dependent foreign keys)
    https://stackoverflow.com/questions/139630/whats-the-difference-between-truncate-and-delete-in-sql  
*/

/*
    After further inspection, the methods joining and connecting the data to load
    was misguided and a convoluted mess - resulting in this enormous number - 
    helped by the poor direction of AI. This project has been illuminating to how 
    AI can respond to what you want but not what you need which can come at odds 
    with this learning journey. Here I turned to my whiteboard and slowed down
    to make purposeful decisive work. 

    Reassessing I rerouted the joins using a new singlular CTE 'period_details', 
    testing the query carefully intending to using the same code to insert/load. 

    The result: 
    70,090 rows ~ 5 rows off estimation

    Implemented the 'on conflict' clause and truncated the queue table before
    populating it again, but with the help of period_details. 

    The result:
    55,920 rows.
*/

/*
    14,175 row reduction?
*/

DROP TABLE IF EXISTS stage_raw; -- Drop raw staging table if it exists (resets query)

-- [EXTRACT]
-- Create a temporary staging table to hold raw CSV data with all columns available for smooth loading
CREATE TEMP TABLE stage_raw (
    date DATE, --- date of log
    clinicID INT, --- clinic indentifying number
    clinicName VARCHAR(255), --- clinic name
    "Hospital and Health Service" VARCHAR(255), --- Catchement area
    Area TEXT, --- visit type e.g. general
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


SELECT date, clinicID, area, COUNT(*)
FROM stage_raw
GROUP BY date, clinicID, area
HAVING COUNT(*) > 1;

/*
    The above code snippet loads master csv,
    selects and groups the master csv by each log
    using: a date, clinic id, and area

    This output produces the count of logs duplicated,
    featuring the same group of fields more than once.

    2834 duplicates are stored in the original dataset
    through formatting from wide to long,
    2834 * 5 = 14,170 rows did not meet conflict conditions

    55,920 rows are an accurate read after normalising and
    accounting for the orginal csv having been cleaned.  
*/

/*************************************************************** misdirected from here due to false error handling; 
Originally, I believed there was a mismatch between stage_raw 
and queue. After detailed investigation in diagnostics.sql, 
I learned the discrepancy came from an upstream count error 
(human oversight), not the ETL logic itself. 
        ********************************************************

        Still 5 rows are technically not passing through in
        the loading phase. 

        11,185 * 5 = 55,925

        load result: 55,920

*/

WITH joined AS (
  SELECT t.date, t.clinic_id, d.period_id, d.visit_id
  FROM long_tiers t
  JOIN period_details d 
    ON t.visit_type = d.visit_type
   AND t.period_name = d.period_name
)
SELECT date, clinic_id, period_id, visit_id, COUNT(*) AS dupe_count
FROM joined
GROUP BY date, clinic_id, period_id, visit_id
HAVING COUNT(*) > 1;

/*
    5 rows are missing as a result of a single stage_raw row not being
    processed via long_tiers. The reason to this skipped in the data
    is unknown,
*/

-- 05/11/2025
...--how did I get to 11,185?
-- count of long_tiers -- 84,108 (long with duplicates)
-- count of stage_raw -- 14,018 (wide with duplicates)
-- count of stage_raw duplicates -- 2834 (wide)
-- legitimate count of stage_raw -- 14,018 - 2834 = 11,184 (wide)
-- hypotheses count of queue -- 11,184 * 5 = 55,920 (long)



-- ####################################################################### --
--                            Handling NULLs in Data                       --
-- ####################################################################### --

SELECT patients_waiting IS NULL
FROM queue; -- check for nulls, none available!

/*

-- Observation:
The master CSV uses '-' for zero or missing values in 'patients_waiting' 
and 'patients_treated'. COPY converts '-' to NULL, which later becomes 0 
when cast to integer. This preserves numeric consistency while avoiding 
misinterpretation of missing vs zero data.

*/

-- ####################################################################### --
--                           Checking for Outliers                         --
-- ####################################################################### --

SELECT patients_waiting, date, clinic_id
FROM queue
ORDER BY patients_waiting DESC;

/*

-- Observation:
The number of patients_waiting has a steady gradation of queues, the 
largest attending the same clinic facility - which would point to a 
regularity. Majority of wait queue size sit at 0, due to the function
of wait time tiers. it is important because understanding the natural 
distribution of values helps when computing averages, totals, or 
visualizing trends, preventing misinterpretation of spikes or zeros.

*/

