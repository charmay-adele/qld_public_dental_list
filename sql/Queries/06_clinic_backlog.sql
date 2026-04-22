----------------------------------------------------------------------------------------------------------------------------
-- BACKLOG --
----------------------------------------------------------------------------------------------------------------------------

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
    Clinic A has 15 general patients waiting. A General appointment has a desired wait time of 24 months.
    10 general patients are on time, 5 general patients have a wait time of 48 months.
            /*
            To design this metric capturing the weighted severity of backlog per clinic+quarter+appointment.
            - A field with the average of each desired wait is created per appointment.
            - Excess wait time is determined by the difference in real patient wait time and the average 
              desired wait time. 
              This gives us a proportional measure of how much demand the volume of patients are.   
            */

    startmonth + endmonth / 2 = avg_desired_wait
    Weight = max(0, VisitWeight - DesiredWeight/DesiredWeight) = max(0,)
*/

/*-- ___________________________________________________________________________

        Level 0: Set Up
                            + months to quarters
                            - for backlog we need:
                              > queue: standardised frequency (quarters)
                              > wait_period table: period_id, start_month, end_month, is_desired
                              > join max 'desired_wait' and average of that desired bracket.
*/--

DROP TABLE IF EXISTS quarter_format;

        CREATE TEMPORARY TABLE quarter_format AS
            WITH total_volume AS ( -- group patients by date, appointment, clinic, catchment, period
                    SELECT
                        q.date,
                        q.patients_waiting, 
                        q.patients_treated,
                        wp.period_id,
                        wp.is_desired,
                        wp.start_month,
                        wp.end_month,
                        ap.visit_type AS visit_type,
                        cl.clinic_id,
                        cl.clinic_name,
                        cl.catchment
                    FROM queue q
                    JOIN appointment ap ON ap.visit_id = q.visit_id
                    JOIN appointment_waitperiod awp ON ap.visit_id = awp.visit_id
                                                    AND q.period_id = awp.period_id
                    JOIN wait_period wp ON awp.period_id = wp.period_id
                    JOIN clinic cl ON cl.clinic_id = q.clinic_id
                    GROUP BY q.date, q.patients_waiting, 
                        q.patients_treated, wp.period_id, wp.is_desired, 
                        wp.start_month, wp.end_month, ap.visit_type,
                        cl.clinic_id, cl.clinic_name, cl.catchment
                    )
                        /*
                        truncate date to quarter, 
                        average snapshot of patient activity & 
                        sum the flow of treated patients to maintain data integrity. 
                        */ 
            SELECT -- group by quarter, catchment, clinic, period calculations, where visit type is general
                DATE_TRUNC('quarter', date)::date AS quarter, 
                clinic_name,
                catchment,
                period_id,
                ROUND(AVG(patients_waiting), 0) AS total_waiting,
                ROUND(SUM(patients_treated), 0) AS total_treated,
                is_desired,
                start_month,
                end_month,
                (start_month + end_month) / 2  AS avg_desired_wait,
                (SELECT MAX(end_month) FROM total_volume WHERE is_desired = 'True') AS desired_wait
                        -- this scalar subquery is used to calculated weight in the following CTE: period_weight
                        -- only because we are looking at one type of visit - general.
            FROM total_volume
            WHERE visit_type = 'General'
            GROUP BY quarter, catchment, clinic_name, period_id, is_desired, start_month, end_month;


/*-- ___________________________________________________________________________

        Level 1: Design Weight
                            + How many times over the desired threshold is this patient's midpoint wait?
                            + mental model:
                                - (30[avg months] - 24[desired months]) / 24[desired months] = 0.25[pressure]
*/--



WITH weight_design AS ( -- longer the period, the greater the weight
        SELECT
                quarter,
                clinic_name,
                catchment,
                period_id,
                total_waiting,
        CASE WHEN is_desired = TRUE THEN 0 -- no pressure
                ELSE ROUND(GREATEST(
                    0, 
                    (((start_month + end_month) / 2.0 - desired_wait) -- patient average wait - appointment desired wait
                    /desired_wait) + 1 -- divided by appointment desired wait + add 1 for multiplication
                ),
                2
            )
        END AS excess_wait
        FROM quarter_format
),

/*-- ___________________________________________________________________________

        Level 2: Apply Weight
                            + 
*/-- 

add_weight AS (
        SELECT
        q.quarter,
        q.clinic_name,
        q.catchment,
        q.period_id,
        q.total_waiting,
        CASE WHEN w.excess_wait > 1 
             THEN q.total_waiting * w.excess_wait
             ELSE q.total_waiting END AS total_waiting_adjusted
        FROM quarter_format q
        LEFT JOIN weight_design w ON q.quarter     = w.quarter 
                                 AND q.clinic_name = w.clinic_name
                                 AND q.period_id   = w.period_id
        GROUP BY q.quarter, q.clinic_name, q.catchment, q.period_id, q.total_waiting, q.total_waiting, w.excess_wait
        ORDER BY q.quarter, q.clinic_name, q.catchment, q.period_id
),

/*-- ___________________________________________________________________________

        Catchment Aggregation
*/-- 
catchment_totals AS (
        SELECT 
                quarter, 
                catchment, 
                SUM(total_waiting_adjusted) AS total_waiting_adjusted, 
                SUM(total_waiting) AS total_waiting,
                SUM(total_waiting_adjusted)-SUM(total_waiting) AS backlog
        FROM add_weight
        GROUP BY quarter, catchment
        ORDER BY quarter, catchment
),

clinic_totals AS (
        SELECT 
                quarter, 
                clinic_name, 
                catchment,
                SUM(total_waiting_adjusted) AS total_waiting_adjusted, 
                SUM(total_waiting) AS total_waiting,
                SUM(total_waiting_adjusted) - SUM(total_waiting) AS backlog
        FROM add_weight
        GROUP BY quarter, clinic_name, catchment
        ORDER BY quarter, clinic_name, catchment
)

/*-- ___________________________________________________________________________

      Final Query: includes backlog/waitlist proportion  

*/-- 

SELECT
        quarter,
        catchment,
        clinic_name,
        total_waiting,
        total_waiting_adjusted,
        backlog,
        CASE WHEN total_waiting_adjusted = 0 THEN 0 
        ELSE backlog/total_waiting_adjusted END AS excess_proportion -- lets find the proportion of backlog to total_adjusted
 FROM clinic_totals
 ORDER BY quarter, catchment, clinic_name