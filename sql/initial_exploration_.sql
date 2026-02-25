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
        WITH dates_waiting AS (
                SELECT
                    date, SUM(patients_waiting) AS patients_waiting, appointment.visit_type AS visit_type
                    FROM queue
                    JOIN appointment ON appointment.visit_id = queue.visit_id
                    GROUP BY date, appointment.visit_type
            )
            -- collapse to quarters, averaging sum of waiuting per date. 
                /*   months of quarters are averaged to maintain data integrity   */   
        SELECT 
            DATE_TRUNC('quarter', date)::date AS quarter_start, 
            visit_type,
            ROUND(AVG(patients_waiting), 0) AS total_waiting
        FROM dates_waiting
        GROUP BY quarter_start, visit_type;

SELECT * FROM quarterly_format ORDER BY quarter_start, visit_type;


        

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
            SELECT date,
                SUM(patients_waiting) AS total_waiting,
                SUM(patients_treated) AS total_treated
            FROM queue
            GROUP BY date
            ORDER BY date;

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

-- Which Catchments capture the most patients?

    catchment	           | waiting	| treated   /*
    Metro South	             1005416	  62822
    Metro North	             703905	      66908
    Sunshine Coast	         406656	      25612
    Cairns and Hinterland	 342250	      21413
    Wide Bay	             328303	      34053
    Gold Coast	             309558	      17240
    */
    SQL Query:
    --------------------------------------------------------------------------------------------------
    SELECT catchment, SUM(patients_waiting) AS waiting, SUM(patients_treated) AS treated
    FROM queue
    JOIN clinic ON queue.clinic_id = clinic.clinic_id
    GROUP BY catchment
    ORDER BY waiting DESC;

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

-- Clinics with the most backlog relative to their output?
    /*
    Each quarter a clinic's output is made up of treated patients from a range of appointment types.
    Each Clinic has a proportion of treated patients per appointment type they serviced, 
    and each appointment type has patients waiting with different measures of wait-time severity.

    How do we find the size of backlog relative to treatment of patients?
    
    The proportion of patients waiting for each type of service at a clinic, and the degree they are 
    waiting for appointments will determine the severity of the backlog. The degree to which a clinic 
    has patients waiting for an appointment (backlog) is weighted by an appointment type's desired wait 
    time as a benchmark.

    For Example: 
    Clinic A has 15 are general patients waiting, 5 priority 1 patients waiting.
    General has a desired wait time of 24 months, priority 1 has a desired wait time of 1 month.
    10/15 general patients are on time, 1/5 priority 1 patient is waiting desired time.
    5 general patients have a wait time of 48 months, 4 priority 1 patients have a wait time of 3 months.
    */
    /*
    To design this metric capturing the weighted severity of backlog per clinic+quarter+appointment type.
    - A field with the average of each desired wait is created per appointment.
    - Excess wait time is determined by patients  for each patient waiting, as the difference between their wait 
        time and the average desired wait time for that appointment type, relative to the average desired 
        wait time. This gives us a proportional measure of how much longer than the desired wait time patients are waiting.   

        -- startmonth + endmonth / 2 = avg_desired_wait
    Weight = max(0, VisitWeight - DesiredWeight/DesiredWeight) = max(0,)
    */
    -- CTE Max Desired Wait Time
    WITH desired AS ( 
        SELECT
            a.visit_type,
            MAX(CASE WHEN wp.is_desired THEN wp.end_month END) AS desired_wait
        FROM appointment AS a
        JOIN appointment_waitperiod aw ON a.visit_id = aw.visit_id
        JOIN wait_period wp ON aw.period_id = wp.period_id
        GROUP BY a.visit_type
    ),
    -- CTE Average Desired Wait Time
    avg_desired AS (
        SELECT
            a.visit_type,
            AVG((wp.start_month + wp.end_month) /2.0) AS avg_desired_wait
        FROM appointment AS a
        JOIN appointment_waitperiod aw ON a.visit_id = aw.visit_id
        JOIN wait_period wp ON aw.period_id = wp.period_id
        WHERE wp.is_desired = TRUE
        GROUP BY a.visit_type
    ),
    -- Query to amount proportional weight of backlog severity
    excess_metric AS (
        SELECT 
            a.visit_type, 
            wp.period_id, 
            wp.period_description, 
            ROUND(ad.avg_desired_wait,0) AS avg_desired_wait, 
            wp.is_desired,
            CASE WHEN wp.is_desired = TRUE THEN 0
                ELSE ROUND(GREATEST(
                    0,
                    ((wp.start_month + wp.end_month) / 2.0 - ad.avg_desired_wait)
                    / d.desired_wait
                ),
                2
            )
            END AS excess_wait -- comment here to clarify
                -- The excess wait expresses how long a patient waits beyond the desired wait, 
                -- relative to the target desired wait, capped at zero.
        FROM appointment AS a
        JOIN desired AS d ON a.visit_type = d.visit_type
        JOIN avg_desired AS ad ON a.visit_type = ad.visit_type
        JOIN appointment_waitperiod aw ON a.visit_id = aw.visit_id
        JOIN wait_period wp ON wp.period_id = aw.period_id
        GROUP BY 
        a.visit_type, 
        wp.period_id, 
        wp.period_description, 
        ad.avg_desired_wait,
        wp.is_desired, 
        wp.start_month, 
        wp.end_month, 
        d.desired_wait
    ), -- grain: visit_type x snapshot of time x clinic
    weighted_waittime AS ( 
        SELECT 
            c.clinic_name,
            a.visit_type,
            wp.period_name, 
            wp.period_id,
            dim.date AS date, 
            q.patients_waiting,
            em.excess_wait,
            em.excess_wait * q.patients_waiting AS weighted_excess_wait
        FROM queue q
        JOIN dim_date dim ON q.date = dim.date
        LEFT JOIN clinic c ON c.clinic_id = q.clinic_id
        LEFT JOIN appointment a ON a.visit_id = q.visit_id
        LEFT JOIN appointment_waitperiod aw ON a.visit_id = aw.visit_id
        LEFT JOIN wait_period wp ON wp.period_id = aw.period_id
        LEFT JOIN excess_metric em ON em.visit_type = a.visit_type AND em.period_id = wp.period_id
    )
    -- Final Query: aggregates backlog activity by clinic+quarter+appointment type. 0 severity means no backlog.
    SELECT
        date, clinic_name, visit_type, 
        SUM(weighted_excess_wait) AS backlog_severity
    FROM weighted_waittime
    GROUP BY date, clinic_name, visit_type
    ORDER BY date, clinic_name, visit_type;

-- How do clinics rank across catchements in meeting desired wait times and treatment targets?  
    /*
    Top Clinics by Catchment - Total Waiting vs Treated (Desired Wait Times)
    */
    catchment	       | clinic_name	               | total_waiting	| total_treated/*
    Metro North	         STAFFORD DENTAL CLINIC	         72489	          20402
    Metro North	         ORAL HEALTH CENTRE	             182264	          19551
    Metro South	         BEENLEIGH BEAUDESERT CLUS	     298667	          14358
    Mackay	             MACKAY DENTAL CLINIC	         147961	          12970
    Wide Bay	         HERVEY BAY DENTAL CLINIC	     109018	          11453
    Central Queensland	 ROCKHAMPTON DENTAL CLINIC	     122211	          11297
    */
    SQL Query:
    --------------------------------------------------------------------------------------------------

  SELECT clinic.catchment, clinic.clinic_name,
         SUM(queue.patients_waiting) AS total_waiting,
         SUM(queue.patients_treated) AS total_treated
    FROM queue
    JOIN clinic ON clinic.clinic_id = queue.clinic_id
    JOIN wait_period ON wait_period.period_id = queue.period_id
    WHERE wait_period.is_desired = True
    GROUP BY clinic.catchment, clinic.clinic_name
    ORDER BY total_treated DESC;

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
         --proportions of visit types treated
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