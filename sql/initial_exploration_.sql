-- ####################################################################### --
--                          Preliminary EDA                                --         
-- ####################################################################### --

-- Understand data shape, missing values, relationships
-----------------------------------------------------------------------------

/* Geography & System Structure */
--------------------------------------------------------------------------------------------------
-- Count of rows in queue table:                                                                
        55,920
    SQL Query:
    --------------------------------------------------------------------------------------------------
        SELECT COUNT(*) AS total_rows FROM queue;
  
-- Count of unique clinics:                                                                     
        113
    SQL Query:
    --------------------------------------------------------------------------------------------------
        SELECT COUNT(DISTINCT clinic_id) AS unique_clinics FROM queue;

-- Count of clinics per catchment area:                                                         
        1. South West                13
        2. Cairns and Hinterland     13
        3. Metro North               12
        4. Darling Downs             10
        5. Wide Bay                  8
        6. Central Queensland        8
        7. Metro South               8
        8. West Moreton              7
        9. Sunshine Coast            7
        10.Townsville                7
        11. Mackay                   6
        12. Gold Coast               5
        13. North West               4
        14. Torres and Cape          3 
    SQL Query:
    --------------------------------------------------------------------------------------------------  
        SELECT clinic.catchment, COUNT(DISTINCT queue.clinic_id) AS clinic_count
        FROM queue
        JOIN clinic ON clinic.clinic_id = queue.clinic_id
        GROUP BY clinic.catchment
        ORDER BY clinic_count DESC;

-- What are clusters? Groups of clinics in a geographical area?
        correct

    SQL Query
    --------------------------------------------------------------------------------------------------                               
    SELECT clinic_id, clinic_name, catchment
    FROM clinic
    WHERE clinic_id IN ('157', '155','154');

-- Date range of data:                                                                          
        oldest visit - 2020-02-29, newest visit - 2025-06-30

     SQL Query:
    --------------------------------------------------------------------------------------------------  
        SELECT 
        MIN(date) AS oldest_visit, 
        MAX(date) AS newest_visit
        FROM queue;   

-- What months have a gap in data? Which quarters are paritial? 

    -- Data collection changed from monthly to quarterly in 2023 Q2
    -- Prior to this, some months were missing data, possibly due to reporting issues or data availability.
    -- From 2024 onwards, data appears complete on a quarterly basis.

    -- Check for missing months - What monthly figures are there for patients waiting vs treated in 2021?
    -- Missing Months:
                2020 --  1, 4-6, 12  - Q1 and Q4 quarter are partial. 
                2021 --  7-12 - Q3 & Q4  
                2022 --   1-6 - Q1 & Q2 
                2023 --   1-3 - Q1
                     --  months are combined into quarters in 2024 and 2025 (to June)
    SQL Query:
    -------------------------------------------------------------------------------------------------------------
        SELECT 
        appointment.visit_type,
        EXTRACT(MONTH FROM date) AS month,
        EXTRACT(QUARTER FROM date) AS quarter,
        EXTRACT(YEAR FROM date) AS year,
            SUM(patients_waiting) AS total_waiting,
            SUM(patients_treated) AS total_treated
        FROM queue
        JOIN appointment ON appointment.visit_id = queue.visit_id
        WHERE appointment.visit_type = 'Clinical Assessment'
          AND EXTRACT(YEAR FROM date) IN (2020, 2021, 2022, 2023, 2024, 2025) 
                                            -- toggled through years to check missing months
        GROUP BY appointment.visit_type, month, quarter, year
        ORDER BY year, quarter, month;

-- Count of clinics servicing each appointment type
    Appointment Type	            Clinic Count
    -------------------------------------------------
    General	                        94
    Priority 3	                    91
    Clinical Assessment	            81
    Priority 2	                    80
    Priority 1	                    78
    General Anaesthetic Category 3	66
    General Anaesthetic Category 2	49
    General Anaesthetic Category 1	47

    SQL Query:
    --------------------------------------------------------------------------------------------------  
        SELECT appointment.visit_type, COUNT(DISTINCT queue.clinic_id) AS clinic_count
        FROM queue
        JOIN appointment ON appointment.visit_id = queue.visit_id
        GROUP BY appointment.visit_type
        ORDER BY clinic_count DESC;


/* System Trends */
--------------------------------------------------------------------------------------------------  
-- Dataset has been collected via seperate methods and will need reformatting to be used for time series analysis.
-- Monthly and Quarterly records are transformed to level quarterly intervals maintaining data integrity.


    DROP TABLE IF EXISTS quarterly_format;

        CREATE TEMPORARY TABLE quarterly_format AS
            WITH total_volume AS (
                    SELECT
                        date, 
                        SUM(patients_waiting) AS patients_waiting, 
                        SUM(patients_treated) AS patients_treated, 
                        appointment.visit_type AS visit_type,
                        clinic.clinic_id,
                        clinic_name,
                        catchment
                        FROM queue
                        JOIN appointment ON appointment.visit_id = queue.visit_id
                        JOIN clinic ON clinic.clinic_id = queue.clinic_id
                        GROUP BY date, appointment.visit_type, clinic.clinic_id, clinic_name, catchment
                )
                -- collapse to quarters, averaging sum of waiting per date. 
                    /*   months of quarters are averaged to maintain data integrity   */   
            SELECT 
                DATE_TRUNC('quarter', date)::date AS quarter_start, 
                visit_type,
                ROUND(AVG(patients_waiting), 0) AS total_waiting,
                ROUND(SUM(patients_treated), 0) AS total_treated,
                clinic_id,
                clinic_name,
                catchment
            FROM total_volume
            GROUP BY quarter_start, visit_type, clinic_id, clinic_name, catchment;

SELECT * FROM quarterly_format ORDER BY quarter_start, visit_type;

-- average proportion of visit_types

    WITH quarterly_visit_total AS ( -- waitlist of each visit_type + quarter
        SELECT
        quarter_start AS quarter,
        SUM(total_waiting) AS total_waitlist,
        visit_type
    FROM quarterly_format
    GROUP BY quarter_start, visit_type
    )
    SELECT -- average of those quarters
    visit_type,
    ROUND(AVG(qvt.total_waitlist),0) AS avg_visit_list,
    ROUND(
        AVG(qvt.total_waitlist)*100 -- partial figure
            /SUM(AVG(qvt.total_waitlist))OVER(), -- define total figure
            2) AS pct_of_list
    FROM quarterly_visit_total qvt
    GROUP BY visit_type;

-- Average catchment capacity per quarter
    WITH clinic_totals AS (
        SELECT 
            quarter_start,
            SUM(total_waiting) AS clinic_waiting_total,
            SUM(total_treated) AS clinic_treated_total,
            clinic_id,
            clinic_name,
            catchment
    FROM quarterly_format
        WHERE visit_type = 'General'
        GROUP BY quarter_start, clinic_id, clinic_name, catchment
    )

    SELECT
    quarter_start,
    SUM(clinic_waiting_total) AS Catchment_total_waiting,
    SUM(clinic_treated_total) AS Catchment_total_treated,
    catchment,
        ROUND(SUM(clinic_treated_total)/NULLIF(SUM(clinic_waiting_total),0), 3) AS avg_capacity_ratio,
        ROUND((SUM(clinic_treated_total)/NULLIF(SUM(clinic_waiting_total),0))*100, 2) AS avg_capacity_pct,
        ROUND(1 / NULLIF((SUM(clinic_treated_total) / NULLIF(SUM(clinic_waiting_total),0)), 0),0) AS avg_n_qtr_to_100pct,
        3 * ROUND(1/NULLIF((SUM(clinic_treated_total) / NULLIF(SUM(clinic_waiting_total),0)),0),0) AS avg_total_months
    FROM clinic_totals
    GROUP BY quarter_start, catchment;

-- Count of Clinics per Catchment
    SELECT COUNT(DISTINCT clinic_name), catchment
    FROM quarterly_format
    GROUP BY catchment;

-- Total waiting list per catchment each quarter
    SELECT
        quarter_start AS quarter,
        SUM(total_waiting) AS total_waitlist,
        catchment
    FROM quarterly_format
    WHERE visit_type = 'General'
    GROUP BY quarter_start, catchment;

-- Clinics per Catchment
    WITH clinic_totals AS (
        SELECT 
            quarter_start,
            SUM(total_waiting) AS clinic_waiting_total,
            SUM(total_treated) AS clinic_treated_total,
            clinic_id,
            clinic_name,
            catchment
    FROM quarterly_format
        WHERE visit_type = 'General'
        GROUP BY quarter_start, clinic_id, clinic_name, catchment
    )

    SELECT
    quarter_start,
    ct.clinic_id,
    ct.clinic_name,
    clinic_waiting_total,
    clinic_treated_total,
    SUM(clinic_waiting_total)OVER(PARTITION BY catchment, quarter_start ORDER BY quarter_start) AS catchment_total,
    catchment,
    ROUND(clinic_treated_total/NULLIF(clinic_waiting_total,0), 3) AS capacity_ratio,
    ROUND((clinic_treated_total/NULLIF(clinic_waiting_total,0))*100, 2) AS capacity_pct,
    ROUND(1 / NULLIF((clinic_treated_total / NULLIF(clinic_waiting_total,0)), 0),0) AS n_qtr_to_100pct,
    3 * ROUND(1/NULLIF((clinic_treated_total / NULLIF(clinic_waiting_total,0)),0),0) AS total_months
    FROM clinic_totals ct
    ORDER BY clinic_waiting_total ASC;





-- How have waiting list volumes changed over time? Are there seasonal or cyclical patterns occuring - is that tied to recommended wait times?

    -- Monthly Totals of Patients Waiting and Treated
        date        | total_waiting | total_treated/*
        2020-02-29	  145990	      6701
        2020-03-31	  145432	      4720
        2020-07-31	  156277	      2958
        2020-08-31	  152711	      4801
        2020-09-30	  152951	      6551
        */

        SQL Query:
        --------------------------------------------------------------------------------------------------------
            EXPLAIN ANALYZE
            SELECT date,
                SUM(patients_waiting) AS total_waiting,
                SUM(patients_treated) AS total_treated
            FROM queue
            GROUP BY date            ORDER BY date;
            ---
            -- CREATE INDEX idx_date ON queue(date);
            -- EXPLAIN ANALYZE < prior to query, to examine execution
            
            --- List all indexes on the queue table
            -- SELECT indexname, indexdef
            -- FROM pg_indexes
            -- WHERE tablename = 'queue';

    -- Grouped by Recommended Wait Time Period Tiers
        date       | period_tier | is_desired | period_description | total_waiting | total_treated/*
        2020-02-29	 Short	       False	     1–2 months	         396	         1437
        2020-02-29	 Short	       False	     3–6 months	         3124	         894
        2020-02-29	 Short	       True	         6–12 months	     7328	         618
        2020-02-29	 Short	       True	         12–24 months	     41571	         2958
        2020-02-29	 Moderate	   False	     12–18 months	     3554	         390
        2020-02-29	 Moderate	   False	     2–3 months	         162	         444
        2020-02-29	 Moderate	   False	     6–9 months	         1086	         490
        2020-02-29	 Moderate	   False	     24–36 months	     372	         321
        */
        SQL Query:
        --------------------------------------------------------------------------------------------------------
            SELECT 
            date,
            wait_period.period_tier, wait_period.is_desired, wait_period.period_description,
                SUM(queue.patients_waiting) AS total_waiting,
                SUM(queue.patients_treated) AS total_treated
            FROM queue
            JOIN appointment_waitperiod ON appointment_waitperiod.period_id = queue.period_id
            JOIN wait_period ON wait_period.period_id = appointment_waitperiod.period_id
            GROUP BY date, wait_period.period_tier, wait_period.is_desired, wait_period.period_description
            ORDER BY date, period_tier DESC;
    
    -- Appointment Types Waiting Volumes Over Time

        date	   | visit_type	                     | total_waiting	| total_treated/*
        2020-02-29	 General	                        128108	            3763
        2020-02-29	 Priority 3	                        10534	            835
        2020-02-29	 Priority 2	                        4456	            792
        2020-02-29	 General Anaesthetic Category 3	    1815	            120
        2020-02-29	 Priority 1	                        554	                524
        2020-02-29	 General Anaesthetic Category 2	    434	                67 
        */
        SQL Query:
        -------------------------------------------------------------------------------------------------------
            SELECT 
            date,
            appointment.visit_type,
                SUM(queue.patients_waiting) AS total_waiting,
                SUM(queue.patients_treated) AS total_treated
            FROM queue
            JOIN appointment ON appointment.visit_id = queue.visit_id
            GROUP BY date, appointment.visit_type
            ORDER BY date, total_waiting DESC;

    -- Proportion of appointment types treated
        /*  Total Treated: 348,487
        */
        visit_type	                      | treated 	  | pct_of_total_treated/*
        Clinical Assessment	                29014	        8.33%
        General	                            205703	 	    59.03%
        General Anaesthetic Category 1	    844	 	        0.24%
        General Anaesthetic Category 2		2892	 	    0.83%
        General Anaesthetic Category 3		5481	        1.57%
        Priority 1	                        21733		    6.24%
        Priority 2	                        44176		    12.68%
        Priority 3	                        38644	  	    11.09%
        */
        
        

        SQL Query:
        -------------------------------------------------------------------------------------------------------
            SELECT
                visit_type,
                treated,
                total_treated,
                CONCAT(
                    ROUND(treated::numeric / NULLIF(total_treated, 0) * 100, 2),
                    '%'
                ) AS pct_of_total_treated
            FROM (
                SELECT
                    a.visit_type,
                    SUM(q.patients_treated) AS treated,
                    SUM(SUM(q.patients_treated)) OVER () AS total_treated
                FROM queue q
                JOIN appointment a ON a.visit_id = q.visit_id
                GROUP BY a.visit_type
            ) s
            ORDER BY visit_type;

    -- Quarterly percentage of total waiting per type of visit
        quarter_start	visit_type	                    total_waiting	pct_of_total_waiting
        2020-01-01	    Clinical Assessment	            101	            0.07
        2020-01-01	    General	                        127635	        87.59
        2020-01-01	    General Anaesthetic Category 1	26	            0.02
        2020-01-01	    General Anaesthetic Category 2	445	            0.31
        2020-01-01	    General Anaesthetic Category 3	1812	        1.24
        2020-01-01	    Priority 1	                    571	            0.39
        2020-01-01	    Priority 2	                    4540	        3.12
            
        SQL Query:
        -------------------------------------------------------------------------------------------
            SELECT 
            quarter_start, visit_type, total_waiting,
                ROUND(SUM(total_waiting)*100/SUM(SUM(total_waiting))OVER(PARTITION BY quarter_start),2) AS pct_of_total_waiting
            FROM quarterly_format AS qf
            GROUP BY quarter_start, visit_type, total_waiting
            ORDER BY quarter_start, visit_type ASC;

            SELECT 
            quarter_start, SUM(total_waiting) AS quarter_total_waiting,
                ROUND(SUM(total_waiting)*100/SUM(SUM(total_waiting))OVER(PARTITION BY quarter_start),2) AS pct_of_total_waiting
            FROM quarterly_format AS qf
            GROUP BY quarter_start;

            
-- multiple select statments -- this needs a temp table to be repurposed. 


    -- ***Waiting trends across different service areas (e.g., general vs. priority treatment)?
        -- example previous 2 years
        quarter | year  | visit	  |total_waiting | total_treated | pct_change_waiting /*
        3	     2023	 General	    119,700	        14,907	    -65.63%
        4	     2023	 General	    125,064	        11,162	      4.48%
        1	     2024	 General	    126,987	        14,357	      1.54%
        2	     2024	 General	    130,940	        13,246	      3.11%
        3	     2024	 General	    131,624	        17,823	      0.52%
        4	     2024	 General	    136,236	        12,426	      3.50%
        1	     2025	 General	    140,165	        12,726	      2.88%
        2	     2025	 General	    147,712	        11,475	      5.38%
        */
        SQL Query:
        ----------------------------------------------------------------------------------------------------------
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
    
        -- Left join quarter_totals to all_combinations - filling in missing combinations with NULLs
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

-- Total waiting and treated per period tier over time *dead end*
    /* 
    Migration of patients flowing through tiers deemed untraceable due to aggregation of the data.

        Migration across tiers would be a helpful key to understanding the dynamics of the waiting list.
      Supporting our question of "How effectively are Queensland public dental clinics managing patient 
      demand across services and catchments?". However without knowing a tier's new and removed patients, 
      we can only observe aggregate numbers per tier per quarter.  

    */ 
     SQL Query:
    --------------------------------------------------------------------------------------------------------
        WITH grouped_periods AS (
            SELECT 
                EXTRACT(QUARTER FROM queue.date) AS quarter,
                EXTRACT(YEAR FROM queue.date) AS year,
                wait_period.period_tier, wait_period.period_description, wait_period.is_desired,
                wait_period.period_name, appointment.visit_type,
                SUM(queue.patients_waiting) AS total_waiting,
                SUM(queue.patients_treated) AS total_treated
            FROM queue
            JOIN appointment_waitperiod ON appointment_waitperiod.period_id = queue.period_id
            JOIN wait_period ON wait_period.period_id = appointment_waitperiod.period_id
            JOIN appointment ON appointment.visit_id = queue.visit_id
            GROUP BY quarter, year, wait_period.period_tier, wait_period.period_description, wait_period.is_desired, wait_period.period_name, appointment.visit_type
        )

        SELECT 
            gp.quarter, gp.year, gp.period_name, gp.period_description, gp.is_desired,
            SUM(gp.total_waiting) AS total_waiting,
            SUM(gp.total_treated) AS total_treated
        FROM grouped_periods AS gp
        WHERE gp.visit_type = 'Clinical Assessment'
        GROUP BY gp.quarter, gp.year, gp.period_name, gp.period_description, gp.is_desired
        ORDER BY gp.year, gp.quarter, gp.period_name, total_waiting DESC;

        -- Are the number of patients waiting a result at the end of the period? left over patients that do not get treated?
        -- If so, then the total waiting would not necessarily equal the total treated.
        -- This would explain why the sums do not match up (eg. 537 waiting, 1508 treated in the same period). 
        -- Does percentage change in waiting mean anything in this context? If we have to account for the proportion of patients as a whole? 
        -- the relationship would be:
        -- total patients = patients waiting + patients treated (per period)
        -- Therefore, if we want to understand the dynamics of waiting lists, we need to consider both treated and waiting patients together.
        -- 1508 treated + 537 waiting = 2045 total patients in that period.
        -- Percentage change in waiting could be more meaningful if we consider it in relation to total patients.

/* System Demands */
--------------------------------------------------------------------------------------------------

-- Top 5 catchment areas (volume) of patients: total waiting, total treated, % of total treated, % of total waiting

    Northern Suburbs has treated more patients (19.2%), while having comparitively smaller waiting list (16.0%)
        Catchment Area	        | Waiting	  | Treated	  | Total % Treated	| Total % Waiting
    --------------------------------------------------------------------------------------------------------------------                        
      1. Metro South	         1,005,416	    62,822	    18.0%	           22.9%
      2. Metro North	         703,905	    66,908	    19.2%	           16.0%
      3. Sunshine Coast	         406,656	    25,612	    7.3%	           9.2%
      4. Cairns and Hinterland	 342,250	    21,413	    6.1%	           7.8%
      5. Wide Bay	             328,303	    34,053	    9.8%	           7.5%   

    /*  
    Note: ‘Waiting’ and ‘Treated’ represent different patient cohorts. 
    Percentages are calculated within each group (share of total waiting and share of total treated). 
    They should not be interpreted as treatment conversion rates.
    */

    SQL Query:
    --------------------------------------------------------------------------------------------------  
        SELECT clinic.catchment, 
                SUM(queue.patients_waiting) AS total_waiting,
                CONCAT(ROUND(SUM(queue.patients_waiting) * 100.0 / SUM(SUM(queue.patients_waiting)) OVER(), 1), '%') AS pct_total_waiting, 
                SUM(queue.patients_treated) AS total_treated, 
                CONCAT(ROUND(SUM(queue.patients_treated) * 100.0 / SUM(SUM(queue.patients_treated)) OVER(), 1), '%') AS pct_total_treated
        FROM queue
        JOIN clinic ON clinic.clinic_id = queue.clinic_id
        GROUP BY clinic.catchment
        ORDER BY total_waiting DESC
        LIMIT 5;

-- Top 5 clinics with highest volume of treated patients?
        Clinic Name                   | Catchment     | Waiting   | Treated | 
    -------------------------------------------------------------------------
        1. ORAL HEALTH CENTRE	        Metro North	    224,266	    27,921     
        2. STAFFORD DENTAL CLINIC	    Metro North	    75,357	    25,468     
        3. BEENLEIGH BEAUDESERT CLUS	Metro South	    298,940	    17,225     
        4. MACKAY DENTAL CLINIC	        Mackay	        148,273	    13,960     
        5. IPSWICH DENTAL CLINIC	    West Moreton	177,318	    13,844

    SQL Query:
    --------------------------------------------------------------------------------------------------
        SELECT clinic.clinic_id, 
               clinic.clinic_name, 
               clinic.catchment, 
               SUM(queue.patients_waiting) AS total_waiting, 
               SUM(queue.patients_treated) AS total_treated
        FROM queue
        JOIN clinic ON clinic.clinic_id = queue.clinic_id
        GROUP BY clinic.clinic_id, clinic.clinic_name, clinic.catchment
        ORDER BY total_treated DESC;
     
-- Top 5 clinics by total waiting volume (cumulative across dataset)  

        1. Beenleigh Beaudesert Cluster  Metro South    2,298,940
        2. GC Southport Health Precint   Gold Coast     234,994
        3. Oral Health Centre            Metro North    224,266
        4. Bayside Cluster               Metro South    193,347
        5. Nathan Inala Cluster          Metro South    190,918
    -- What are clusters? Groups of clinics in a geographical area?
            yes, all clinics in a cluster belong to the same catchment area. That catchment area is South Metro
    -- Why is Beenleigh Beaudesert Cluster so high?
    /*
            It services the Metro South catchment, which has 23% of Queensland's population (1.2 Million people).
            [https://healthtranslationqld.org.au/partners/metro-south-health#:~:text=Metro%20South%20Health%20is%20the,Visit%20the%20website]
    */
    SQL Query:
    --------------------------------------------------------------------------------------------------  
        SELECT queue.clinic_id, clinic.clinic_name, clinic.catchment, SUM(patients_waiting) AS total_waiting, SUM(patients_treated) AS total_treated
        FROM queue
        JOIN clinic ON clinic.clinic_id = queue.clinic_id
        GROUP BY queue.clinic_id, clinic.clinic_name, clinic.catchment
        ORDER BY total_waiting DESC
        LIMIT 5;

/* Clinic & Catchment Comparison */   
--------------------------------------------------------------------------------------------------

SELECT COUNT(DISTINCT catchment)
FROM clinic

-- Which Catchments capture the most patients?
    Catchment               avg_list  avg_general_list
    Metro South	            33694	  32120
    Metro North	            23514	  17400
    Sunshine Coast	        13563	  11903
    Wide Bay	            11295	  10307
    Cairns and Hinterland	11179	   9716

    SQL Query:
    --------------------------------------------------------------------------------------------------  
    WITH quarterly_catchement_total AS ( -- sum of each catchemnt each quarter
        SELECT
        quarter_start AS quarter,
        SUM(total_waiting) AS total_waitlist,
        SUM(CASE WHEN visit_type = 'General' THEN total_waiting ELSE 0 END) AS general_waitlist,
        catchment
    FROM quarterly_format
    GROUP BY quarter_start, catchment
    )
    SELECT 
    catchment,
    ROUND(AVG(total_waitlist),0) AS avg_waitlist,
    ROUND(AVG(general_waitlist),0) AS avg_general_waitlist
    FROM quarterly_catchement_total
    GROUP BY catchment
    ORDER BY avg_general_waitlist DESC;
:: below need quarterly_format update::
-- Which specific Catchments have the largest patient base (at a given time) and are visits seasonal?  
    catchment	        quarter	year	total_waiting	total_treated
    Metro South	        1	    2020	68292	        1861
    Metro North	        1	    2020	52775	        1850
    Wide Bay	        1	    2020	20708	        1280
    Central Queensland	1	    2020	16292	        902
    Mackay	            1	    2020	13150	        882
    Gold Coast	        1	    2020	18991	        881
   
    SQL Query:
    --------------------------------------------------------------------------------------------------
        SELECT 
        clinic.catchment,
        EXTRACT(QUARTER FROM date) AS quarter, 
        EXTRACT(YEAR FROM date) AS year,
            SUM(patients_waiting) AS total_waiting,
            SUM(patients_treated) AS total_treated
        FROM queue
        JOIN clinic ON clinic.clinic_id = queue.clinic_id
        GROUP BY quarter, year, clinic.catchment
        ORDER BY year, quarter, SUM(patients_treated) DESC;

-- What is the average number of patients treated per clinic per period? 
        /*
        224.83 Patients are treated by each clinic on average per quarter.
        Clinics with top treated quarterly averages:
        */
        clinic_name	                | avg_treated_per_clinic_qtr/*
        ORAL HEALTH CENTRE	          1745.06
        STAFFORD DENTAL CLINIC	      1591.75
        BEENLEIGH BEAUDESERT CLUS	  1076.56
        MACKAY DENTAL CLINIC	      872.50
        IPSWICH DENTAL CLINIC	      865.25
        ROCKHAMPTON DENTAL CLINIC	  854.50
        HERVEY BAY DENTAL CLINIC	  834.31
    */
    SQL Query:
    --------------------------------------------------------------------------------------------------
        -- Not including dim_date nulls to avoid skewing the average
        WITH clinics_per_qtr AS (SELECT 
        clinic.clinic_id, clinic.clinic_name,
        EXTRACT(YEAR FROM date) AS year,
        EXTRACT(QUARTER FROM date)AS quarter,
        SUM(queue.patients_treated) AS treated
        FROM queue
        JOIN clinic ON clinic.clinic_id = queue.clinic_id
        GROUP BY clinic.clinic_id, year, quarter 
        ORDER BY clinic.clinic_id, year, quarter)

        SELECT ROUND(AVG(treated), 2) AS avg_treated_per_qtr
        FROM clinics_per_qtr

        -- Average treated per clinic & quarter
            WITH clinic_qtr_treated AS(
                SELECT 
            clinic.clinic_id, clinic.clinic_name AS clinic_name,
            EXTRACT(YEAR FROM date) AS year,
            EXTRACT(QUARTER FROM date)AS quarter,
            SUM(queue.patients_treated) AS sum_treated
            FROM queue
            JOIN clinic ON clinic.clinic_id = queue.clinic_id
            GROUP BY clinic.clinic_id, year, quarter
            ORDER BY clinic.clinic_id
            )
            SELECT clinic_name, ROUND(AVG(sum_treated), 2) AS avg_treated_per_clinic_qtr
            FROM clinic_qtr_treated
            GROUP BY clinic_name
            ORDER BY avg_treated_per_clinic_qtr DESC;
    
-- Given appointment type, what percentage of patients are treated within the recommended timeframe? 
    visit_type	                    | pct_treated_within_recommended_timeframe/*
    General	                         86.72%
    Priority 3	                     76.10%
    General Anaesthetic Category 3	 64.17%
    Clinical Assessment	             62.62%
    Priority 1	                     54.58%
    Priority 2	                     47.85%
    General Anaesthetic Category 1	 39.34%
    General Anaesthetic Category 2	 32.26%
    */
    SQL Query:
    --------------------------------------------------------------------------------------------------
    
    SELECT appointment.visit_type,
         CONCAT(ROUND(100.0 * SUM(CASE WHEN wait_period.is_desired = True THEN queue.patients_treated ELSE 0 END) /
         NULLIF(SUM(queue.patients_treated), 0), 2), '%') AS pct_treated_within_recommended_timeframe
         -- proportions of visit types treated
         -- pct_of_total_treated_across_all_types shows the percentage of all treated patients accounted for by each visit type
         -- Proportion of treated patients per visit type out of total treated across all types
    FROM queue
    JOIN appointment ON appointment.visit_id = queue.visit_id
    JOIN wait_period ON wait_period.period_id = queue.period_id
    GROUP BY appointment.visit_type
    ORDER BY pct_treated_within_recommended_timeframe DESC;

    -- Proportion of appointment types treated
        /*  Total Treated: 348,487
        */
        visit_type	                      | treated 	  | pct_of_total_treated/*
        Clinical Assessment	                29014	        8.33%
        General	                            205703	 	    59.03%
        General Anaesthetic Category 1	    844	 	        0.24%
        General Anaesthetic Category 2		2892	 	    0.83%
        General Anaesthetic Category 3		5481	        1.57%
        Priority 1	                        21733		    6.24%
        Priority 2	                        44176		    12.68%
        Priority 3	                        38644	  	    11.09%
        */
        
        Patient Waiting is the snap shot of the day, Patients treated given the number of patients seen at a given period.
        They are not mutually exclusive. 

        SQL Query:
        -------------------------------------------------------------------------------------------------------
            SELECT
                visit_type,
                treated,
                total_treated,
                CONCAT(
                    ROUND(treated::numeric / NULLIF(total_treated, 0) * 100, 2),
                    '%'
                ) AS pct_of_total_treated
            FROM (
                SELECT
                    a.visit_type,
                    SUM(q.patients_treated) AS treated,
                    SUM(SUM(q.patients_treated)) OVER () AS total_treated
                FROM queue q
                JOIN appointment a ON a.visit_id = q.visit_id
                GROUP BY a.visit_type
            ) s
            ORDER BY visit_type;
    
/* Service Availability */  
-------------------------------------------------------------------------------------------------- 
-- How many clinics service a type of appointment? Are there appointment types under serviced/or oversubscribed?

    SELECT c.catchment,a.visit_type, COUNT(DISTINCT q.clinic_id) AS num_clinics_servicing
    FROM queue q
    JOIN appointment a ON a.visit_id = q.visit_id
    JOIN clinic c ON q.clinic_id = c.clinic_id
    GROUP BY c.catchment, a.visit_type
    ORDER BY c.catchment

-- Average quarterly wait per clinic+period_tier
    SELECT DISTINCT(queue.clinic_id), clinic.clinic_name, ROUND(AVG(patients_waiting), 2) AS avg_patients_waiting, wait_period.period_tier
    FROM queue
    JOIN clinic ON clinic.clinic_id = queue.clinic_id
    JOIN appointment_waitperiod ON appointment_waitperiod.period_id = queue.period_id
    JOIN wait_period ON wait_period.period_id = appointment_waitperiod.period_id
    GROUP BY queue.clinic_id, clinic.clinic_name, wait_period.period_tier
    ORDER BY avg_patients_waiting DESC;
 

/*
SERVICE CHARACTERISTICS:
-- Which clinics or catchments have the longest patient waiting times, and how does this vary over time?
-- What are the total number of patients waiting each year for each catchment area.
-- Top clinics with count of treated patients
-- How many patients are going through clinical assessment at one time... Visit_Type : Clinical Assessment
-- Year on year changes in general patient numbers
-- What are the types of care that are in most demand through the public dental system?
-- What are the yearly distribution of these visit types, and the rate a patient is treated per schedule?
-- Priority care, General anaesthetic, General care? find the roll over of waiting/treated patients quarter to quarter
*/
-----------------------------------------------------------------------------