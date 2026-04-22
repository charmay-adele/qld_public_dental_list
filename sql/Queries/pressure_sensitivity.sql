
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
   /* -- CTE Max Desired Wait Time
    WITH desired AS ( 
        SELECT
            a.visit_type,
            MAX(CASE WHEN wp.is_desired THEN wp.end_month END) AS desired_wait
        FROM appointment AS a
        JOIN appointment_waitperiod aw ON a.visit_id = aw.visit_id
        JOIN wait_period wp ON aw.period_id = wp.period_id
        GROUP BY a.visit_type
    ),*/
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
    -- Final Query: aggregates backlog activity by clinic+quarter+appointment type. 
    -- 0 severity means no backlog. lower numbers the better
    SELECT
        date, clinic_name, visit_type, 
        SUM(weighted_excess_wait) AS backlog_severity
    FROM weighted_waittime
    WHERE visit_type = 'General'
    GROUP BY date, clinic_name, visit_type
    ORDER BY date, clinic_name, visit_type;


    