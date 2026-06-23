
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

/*-- ___________________________________________________________________________--*/

SELECT
    catchment,
    ROUND(SUM(total_waiting) / SUM(SUM(total_waiting)) OVER () * 100, 2) AS pct_of_qld_waitlist
FROM quarterly_format
WHERE visit_type = 'General'
AND quarter >= '2023-07-01'
GROUP BY catchment
ORDER BY pct_of_qld_waitlist DESC;