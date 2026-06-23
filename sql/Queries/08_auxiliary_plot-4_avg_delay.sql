/* ___ Average Torres and Cape delayed wait___*/

DROP TABLE IF EXISTS quarter_format;

        CREATE TEMPORARY TABLE quarter_format AS
            WITH total_volume AS ( -- sum of treated patients
                    SELECT
                        DATE_TRUNC('quarter',q.date)::date AS quarter_start,
                        ROUND(SUM(q.patients_treated),0) AS total_treated,
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
                    WHERE ap.visit_type = 'General'
                    GROUP BY q.date, wp.period_id, wp.is_desired, 
                        wp.start_month, wp.end_month, ap.visit_type,
                        cl.clinic_id, cl.clinic_name, cl.catchment
                    ),
                snapshot_setup AS ( -- 3 monthly set up -- sum of waiting patients
                -- PER PERIOD_ID
                        SELECT
                        q.date,
                        ap.visit_type,
                        q.clinic_id,
                        clinic.clinic_name,
                        clinic.catchment,
                        q.period_id, wp.is_desired, wp.start_month, wp.end_month,
                        SUM(patients_waiting) AS total_waiting   -- snapshot: sum across clinics on that date
                        FROM queue q
                        JOIN clinic      ON clinic.clinic_id     = q.clinic_id
                        JOIN appointment ap ON ap.visit_id = q.visit_id
                        JOIN appointment_waitperiod awp ON ap.visit_id = awp.visit_id
                                                        AND q.period_id = awp.period_id
                        JOIN wait_period wp ON awp.period_id = wp.period_id
                        WHERE EXTRACT(MONTH FROM q.date) IN (3, 6, 9, 12)
                        GROUP BY
                        q.date,
                        ap.visit_type,
                        q.clinic_id,
                        clinic.clinic_name,
                        clinic.catchment,
                        q.period_id, wp.is_desired, wp.start_month, wp.end_month
                ),
                third_month_snapshot AS ( -- date trunc snapshot_setup to seamless merge with treated patients
                -- PER PERIOD_ID
                        SELECT
                        DATE_TRUNC('quarter', date)::date AS quarter_start,
                        visit_type,
                        clinic_id,
                        clinic_name,
                        catchment,
                        period_id, is_desired, start_month, end_month, --period grains
                        total_waiting
                        FROM snapshot_setup
                ),
                desired_wait_by_type AS (
                SELECT
                        visit_type,
                        MAX(end_month) AS desired_wait
                FROM total_volume
                WHERE is_desired = 'True'
                GROUP BY visit_type
                )
            SELECT -- join treated and processed waiting patients - start backlog metric.
                t.quarter_start AS quarter,
                t.visit_type,
                t.clinic_id,
                t.clinic_name,
                t.catchment,
                t.period_id, t.is_desired, t.start_month, t.end_month, --period grains
                SUM(t.total_treated) AS total_treated,
                s.total_waiting,
                (t.start_month + t.end_month) / 2  AS avg_desired_wait,
                dw.desired_wait
                FROM total_volume t
                LEFT JOIN third_month_snapshot s
                ON  s.quarter_start = t.quarter_start
                AND s.clinic_id     = t.clinic_id
                AND s.visit_type    = t.visit_type
                AND s.period_id     = t.period_id
                JOIN desired_wait_by_type dw ON dw.visit_type = t.visit_type
            GROUP BY quarter, t.visit_type, t.catchment, t.clinic_id, t.clinic_name, s.total_waiting, t.period_id, t.is_desired, t.start_month, t.end_month, dw.desired_wait;



/*________________________________________________________________________________*/

SELECT 
    catchment,
    ROUND(AVG((start_month + end_month) / 2.0),0) AS avg_wait_months,
    ROUND(AVG((start_month + end_month) / 2.0)/12,1) AS avg_wait_years
FROM quarter_format
WHERE is_desired = 'False'
AND catchment = 'Torres and Cape'
GROUP BY catchment