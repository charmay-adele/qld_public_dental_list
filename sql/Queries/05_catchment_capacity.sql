----------------------------------------------------------------------------------------------------------------------------
-- Flow Efficiency --
----------------------------------------------------------------------------------------------------------------------------

/*
    This query produces the throughput of catchments and the spread of clinics
    within these catchments to support analysis of flow efficiency and homogeneity. 

    Why the mean ratio of catchments? Inclusivity.
    Successful clinics with empty waitlists can not be measured fairly for a
    treatment rate unless aggregated in the mean. Although excluded from the 
    standard deviation, using this method successful clinics underwrite general 
    observations.

    
    Why median ratio, and median absolute deviation?
    median deviation is a median in the difference of ratios across clinics (that have ratios). 
    This deviation metric excludes clinics that can not have capacity measured,
    positives - baseline is not skewed heavily by uncapped top performing outliers
    negatives - uses partial dataset which excludes unmeasurable clinics (i.e the best performers)
    benefits - median centers on clinics with ratios not influenced by their size 
    (that have leading to dramatic distributions), while also being pulled away from 
    successful clinics. This delivers a more balanced representation of catchment 
    performance in terms of flow efficiency.

    Homogeneity - shows up in the spread of ratios of clinics referencing the mean or the median.
    This is important to describe a catchments inequity across clinics. Does a catchment's clinics 
    live in a tight band of ratios and their spread consistant across the timeline? or are they 
    sporatic within a catchment (wide spread in terms of performance) and what consistancy do these 
    clinics have quarter or quarter. Consistency in clinics across a catchment level's spread and 
    quarterly trend. 


*/

/*-- ___________________________________________________________________________

        Level 0: Set Up
                            + months to quarters
*/--

DROP TABLE IF EXISTS quarterly_format;

        CREATE TEMPORARY TABLE quarterly_format AS
            WITH total_volume AS ( -- group patients by date, appointment, clinic, catchment
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

-- truncate date to quarter, average stock of patient activity & aggregate flow of treated patients to maintain data integrity.  
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


/*-- ___________________________________________________________________________

        Level 1: Clinic
                            + quarter
                            + catchment
                            + clinic_name
                            + clinic_capacity_ratio
*/--
WITH clinic_ratio AS (
    SELECT 
            quarter_start,
            catchment,
            clinic_name,
            SUM(total_treated) AS clinic_treated_total,
            SUM(total_waiting) AS clinic_waiting_total,
            ROUND(SUM(total_treated)/NULLIF(SUM(total_waiting),0),3) AS clinic_capacity_ratio
    FROM quarterly_format
        WHERE visit_type = 'General'
        GROUP BY quarter_start, catchment, clinic_name
),
   
/*-- ___________________________________________________________________________

        Level 2: Catchment
                            + quarter
                            + catchment
                            + catchment_capacity_ratio
                            + mean_ratio
                            + stdev_ratio
                            + median_ratio
*/-- 
catchment_stats AS (
    SELECT 
        cl.quarter_start,                                                    -- quarter
        cl.catchment,                                                        -- catchment
        SUM(clinic_treated_total)                                           AS catchment_treated_total,
        SUM(clinic_waiting_total)                                           AS catchment_waiting_total,
        SUM(clinic_treated_total)/SUM(clinic_waiting_total)                 AS mean_ratio,
        STDDEV_POP(cl.clinic_capacity_ratio)                                AS stddev,
        PERCENTILE_CONT(0.5)WITHIN GROUP(ORDER BY cl.clinic_capacity_ratio) AS median_ratio
    FROM clinic_ratio cl
        GROUP BY quarter_start, catchment
        ),

/*-- ___________________________________________________________________________

        Level 3: median absolute deviation calculation
                            + median_difference
*/-- 
mad_setup AS (
    SELECT
        cs.quarter_start,
        cs.catchment,
        cl.clinic_name,
        cs.median_ratio - cl.clinic_capacity_ratio AS median_diff -- mad to be calculated in final query
    FROM clinic_ratio cl
    JOIN catchment_stats cs ON cl.quarter_start = cs.quarter_start
                           AND cl.catchment = cs.catchment
    GROUP BY cs.quarter_start, cs.catchment, cl.clinic_name, cs.median_ratio, cl.clinic_capacity_ratio
)

/*-- ___________________________________________________________________________

        Final Query: catchment level ratios(flow efficiency), mean, stddev, median, mad
                            + median_difference (homogeneity)
*/-- 
SELECT 
    cs.quarter_start AS quarter,
    cs.catchment,
    cs.catchment_waiting_total,
    cs.catchment_treated_total,
    cs.mean_ratio,
    cs.median_ratio,
    cs.stddev AS standard_deviation,
    PERCENTILE_CONT(0.5)WITHIN GROUP(ORDER BY ms.median_diff) AS median_absolute_deviation
FROM catchment_stats cs
JOIN mad_setup ms ON ms.quarter_start = cs.quarter_start 
                 AND ms.catchment = cs.catchment
GROUP BY cs.quarter_start, cs.catchment, cs.catchment_waiting_total, cs.catchment_treated_total, cs.mean_ratio, cs.median_ratio, cs.stddev
ORDER BY cs.quarter_start, cs.catchment     