----------------------------------------------------------------------------------------------------------------------------
-- Flow Efficiency --
----------------------------------------------------------------------------------------------------------------------------

/*
    This query produces the throughput of catchments and the spread of clinics
    within these catchments to support analysis of flow efficiency and homogeneity. 

    Why the mean ratio of catchments?
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

Think about: treatment ratio or capacity percent? which of these are better suited for either median or mean.

update:
clinic capacity is treated/(waiting+treated)*100 = % of treated

treatment_rate is treated/waiting = for every 1 treated x are waiting - 100% 'breakeven' is actually 50% throughput



*/

/*-- ___________________________________________________________________________

        Level 0: Set Up
                            + transform timeseries from months to quarters
                            + consistancy aggregating waiting and treated patients
                            + waiting patients every 3rd month (quarterly snapshot)
                            + treated patients sum of 3 months
*/--

DROP TABLE IF EXISTS quarterly_format;

CREATE TEMPORARY TABLE quarterly_format AS
    WITH total_volume AS ( --the sum of all patients treated
        SELECT
            DATE_TRUNC('quarter', queue.date)::date AS quarter_start,
            appointment.visit_type,
            clinic.clinic_id,
            clinic_name,
            catchment,
            ROUND(SUM(patients_treated), 0) AS total_treated
        FROM queue
        JOIN appointment ON appointment.visit_id = queue.visit_id
        JOIN clinic      ON clinic.clinic_id     = queue.clinic_id
        GROUP BY
            quarter_start,
            appointment.visit_type,
            clinic.clinic_id,
            clinic_name,
            catchment
    ),
    snapshot_setup AS ( -- 3 monthly set up
        SELECT
            queue.date,
            appointment.visit_type,
            clinic.clinic_id,
            clinic_name,
            catchment,
            SUM(patients_waiting) AS total_waiting   -- snapshot: sum across clinics on that date
        FROM queue
        JOIN appointment ON appointment.visit_id = queue.visit_id
        JOIN clinic      ON clinic.clinic_id     = queue.clinic_id
        WHERE EXTRACT(MONTH FROM queue.date) IN (3, 6, 9, 12)
        GROUP BY
            queue.date,
            appointment.visit_type,
            clinic.clinic_id,
            clinic_name,
            catchment
    ),
    third_month_snapshot AS ( -- date trunc every 3rd month into quarter to get total waiting
    SELECT
        DATE_TRUNC('quarter', date)::date AS quarter_start,
            visit_type,
            clinic_id,
            clinic_name,
            catchment,
            total_waiting
        FROM snapshot_setup
    )
SELECT -- join total waiting to total volume via quarter_start
    t.quarter_start AS quarter,
    t.visit_type,
    t.clinic_id,
    t.clinic_name,
    t.catchment,
    t.total_treated,
    s.total_waiting
FROM total_volume t
JOIN third_month_snapshot s
    ON  s.quarter_start = t.quarter_start
    AND s.clinic_id     = t.clinic_id
    AND s.visit_type    = t.visit_type;

/*-- ___________________________________________________________________________

        Level 1: Clinic
                            + quarter
                            + catchment
                            + clinic_name
                            + clinic_capacity_ratio
*/--
WITH clinic_capacity AS (
    SELECT 
            quarter,
            catchment,
            clinic_name,
            SUM(total_treated)                                                          AS clinic_treated_total,
            SUM(total_waiting)                                                          AS clinic_waiting_total,
            ROUND(SUM(total_treated)/NULLIF(SUM(total_waiting),0),3)                    AS clinic_treatment_rate,
            ROUND(SUM(total_treated)/NULLIF(SUM(total_waiting+total_treated),0),3)*100  AS clinic_capacity
    FROM quarterly_format
        WHERE visit_type = 'General'
        GROUP BY quarter, catchment, clinic_name
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
        cl.quarter,                                                                 -- quarter
        cl.catchment,                                                               -- catchment
        SUM(cl.clinic_treated_total)                                                AS catchment_treated_total,
        SUM(cl.clinic_waiting_total)                                                AS catchment_waiting_total,
        ROUND(AVG(cl.clinic_capacity),2)                                            AS catchment_mean,
        ROUND(STDDEV_POP(cl.clinic_capacity),2)                                     AS stddev,
        PERCENTILE_CONT(0.5)WITHIN GROUP(ORDER BY cl.clinic_capacity)               AS catchment_median
    FROM clinic_capacity cl
        GROUP BY quarter, catchment
        ),

/*-- ___________________________________________________________________________

        Level 3: median absolute deviation calculation
                            + median_difference
*/-- 
mad_setup AS (
    SELECT
        cs.quarter,
        cs.catchment,
        cl.clinic_name,
        cs.catchment_median - cl.clinic_capacity AS median_diff -- mad to be calculated in final query
    FROM clinic_capacity cl
    JOIN catchment_stats cs ON cl.quarter = cs.quarter
                           AND cl.catchment = cs.catchment
    GROUP BY cs.quarter, cs.catchment, cl.clinic_name, cs.catchment_median, cl.clinic_capacity
)

/*-- ___________________________________________________________________________

        Final Query: catchment level ratios(flow efficiency), mean, stddev, median, mad
                            + median_difference (homogeneity)
*/-- 
SELECT 
    cs.quarter,
    cs.catchment,
    cs.catchment_waiting_total,
    cs.catchment_treated_total,
-- mean capacity per quarter
    ROUND(SUM(cs.catchment_treated_total) OVER (PARTITION BY cs.quarter)/SUM(cs.catchment_waiting_total) OVER (PARTITION BY cs.quarter)*100,2) AS quarter_capacity,
    SUM(cs.catchment_waiting_total) OVER (PARTITION BY cs.quarter) AS waitlist_total,
    SUM(cs.catchment_treated_total) OVER (PARTITION BY cs.quarter) AS waitlist_treated,
    ROUND(cs.catchment_waiting_total/SUM(cs.catchment_waiting_total) OVER (PARTITION BY cs.quarter)*100, 2) AS catchment_pct_of_qld,
    cs.catchment_mean,
    cs.catchment_median,
    cs.stddev AS standard_deviation,
    PERCENTILE_CONT(0.5)WITHIN GROUP(ORDER BY ms.median_diff) AS median_absolute_deviation
FROM catchment_stats cs
JOIN mad_setup ms ON ms.quarter = cs.quarter 
                 AND ms.catchment = cs.catchment
WHERE cs.quarter >= '2023-04-01'
GROUP BY cs.quarter, cs.catchment, cs.catchment_waiting_total, cs.catchment_treated_total, cs.catchment_mean, cs.catchment_median, cs.stddev
ORDER BY cs.quarter, standard_deviation DESC;