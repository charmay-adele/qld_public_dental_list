
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

        Level 1: calculate capacity ratios and percentages per quarter
                            
*/-- 

WITH catchment_totals AS (
     SELECT 
        quarter,
        SUM(total_treated)AS catchment_treated_total,
        SUM(total_waiting)AS catchment_waiting_total,
        ROUND(SUM(total_treated)/NULLIF((SUM(total_waiting)),0), 3) AS totalled_mean_treatment_rate,
        catchment
    FROM quarterly_format
        WHERE visit_type = 'General'
        GROUP BY quarter, catchment
    ),

catchment_treatment_rates AS(
       SELECT
        quarter, 
        catchment,
    -- catchment figures
        catchment_waiting_total,
        catchment_treated_total,
    -- catchment treatment ratio and percentage - for every patient waiting in said cachment # is treated.
        ROUND(catchment_treated_total/NULLIF(catchment_waiting_total,0), 3) AS catchment_treatment_ratio,
        ROUND((catchment_treated_total/NULLIF(catchment_waiting_total,0))*100, 2) AS catchment_treatment_pct,
    -- clinic quarter treated in months and quarters
        ROUND(1/NULLIF(ROUND(catchment_treated_total/NULLIF(catchment_waiting_total,0), 3),0),0) AS quarters_to_treat,
        ROUND((1/NULLIF(ROUND(catchment_treated_total/NULLIF(catchment_waiting_total,0), 3),0))*3, 0) AS months_to_treat
    FROM catchment_totals
    WHERE quarter >= '2023-04-01'
    GROUP BY quarter, catchment, catchment_waiting_total, catchment_treated_total
    ORDER BY quarter, catchment 
    ),

    /*-- ___________________________________________________________________________

        Final Query: 
                quarter, 
                catchment, 
                treatment_ratio, 
                unaccounted_exists,
                quarters_to_treat, 
                months_to_treat

            The goal: find the number of patients exiting the list each quarter.
        -- patients_cleared_in_24mo = patients_per_month * 24
        -- patients_stuck_beyond_24mo = waitlist - patients_cleared_in_24mo
                                                   
*/-- 
patients_delayed AS (
    SELECT
            DATE_TRUNC('quarter', q.date)::date AS quarter_start,
            c.catchment,
            ROUND(SUM(q.patients_waiting), 0) AS long_waiting_patients
        FROM queue q
        JOIN appointment                ON appointment.visit_id = q.visit_id
        JOIN clinic c                   ON c.clinic_id = q.clinic_id
        JOIN appointment a              ON a.visit_id = q.visit_id
        JOIN appointment_waitperiod awp ON awp.visit_id = a.visit_id
                                        AND q.period_id = awp.period_id
        JOIN wait_period wp             ON wp.period_id = awp.period_id
    WHERE wp.is_desired = 'FALSE'
    AND EXTRACT (MONTH FROM q.date) IN (3,6,9,12)
    AND a.visit_type = 'General'
    GROUP BY
        quarter_start,
        c.catchment
),

patients_cleared AS (
SELECT
    quarter,
    catchment,
    catchment_waiting_total,
    months_to_treat,
    SUM(catchment_waiting_total/months_to_treat)*24 AS patients_cleared_in_24mo
FROM catchment_treatment_rates
GROUP BY quarter, catchment, catchment_waiting_total, months_to_treat
),

patients_beyond AS (
SELECT
    quarter,
    catchment,
    months_to_treat,
    ROUND(patients_cleared_in_24mo, 0) AS patients_cleared_in_24mo,
    ROUND(catchment_waiting_total - SUM(catchment_waiting_total/months_to_treat)*24,0) AS patients_beyond_24mo
FROM patients_cleared p
GROUP BY quarter, catchment, catchment_waiting_total, months_to_treat, patients_cleared_in_24mo
),

patient_interpretation AS (
    SELECT
    b.quarter,
    b.catchment,
    c.catchment_waiting_total,
    c.catchment_treated_total,
    c.catchment_treatment_ratio,
    c.catchment_treatment_pct,
    b.months_to_treat,
    patients_cleared_in_24mo,
    patients_beyond_24mo,
    long_waiting_patients,
    SUM(patients_beyond_24mo - long_waiting_patients) AS exit_results,
    CASE
        WHEN b.months_to_treat <= 24 THEN 'within target'
        WHEN b.months_to_treat > 24 AND SUM(patients_beyond_24mo - long_waiting_patients) > 0 THEN 'exits likely'
        WHEN b.months_to_treat > 24 AND SUM(patients_beyond_24mo - long_waiting_patients) <= 0 THEN 'retention — patients trapped'
    END AS exit_interpretation
FROM patients_beyond b
JOIN patients_delayed d ON b.quarter = d.quarter_start
                        AND b.catchment = d.catchment
JOIN catchment_treatment_rates c ON c.quarter = b.quarter
                                 AND c.catchment = b.catchment
GROUP BY b.quarter, b.catchment, b.months_to_treat, patients_cleared_in_24mo, patients_beyond_24mo, long_waiting_patients,c.catchment_waiting_total,c.catchment_treated_total,c.catchment_treatment_ratio,c.catchment_treatment_pct
)
-- patients beyond 24mo should be stuck
-- patients waiting long are the ones staying on the list.GROUP BY
-- exit patients are those who left.
    -- + positive numbers mean these people have left
    -- - negative numbers

SELECT
    quarter,
    catchment,
    catchment_waiting_total,
    catchment_treated_total,
    catchment_treatment_ratio,
    catchment_treatment_pct,
    months_to_treat,
    patients_cleared_in_24mo,
    patients_beyond_24mo,
    long_waiting_patients,
    exit_results,
    exit_interpretation
FROM patient_interpretation
GROUP BY quarter, 
catchment,catchment_waiting_total,catchment_treated_total,catchment_treatment_ratio, catchment_treatment_pct, 
months_to_treat, patients_cleared_in_24mo, patients_beyond_24mo, long_waiting_patients, exit_results, exit_interpretation;
