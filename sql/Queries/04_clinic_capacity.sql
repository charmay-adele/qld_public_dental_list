
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

WITH clinic_totals AS (
        SELECT 
            quarter,
            SUM(total_treated) AS clinic_treated_total,
            SUM(total_waiting) AS clinic_waiting_total,
            clinic_id,
            clinic_name,
            catchment
    FROM quarterly_format
        WHERE visit_type = 'General'
        GROUP BY quarter, clinic_id, clinic_name, catchment
    ),
    catchment_totals AS (
     SELECT 
        quarter,
        SUM(total_treated)AS catchment_treated_total,
        SUM(total_waiting)AS catchment_waiting_total,
        ROUND(SUM(total_treated)/NULLIF((SUM(total_waiting)),0), 3) AS mean_treatment_rate,
        catchment,
        CASE 
            WHEN catchment IN ('Torres and Cape','Cairns and Hinterland','Townsville','Mackay') THEN 'North'
            WHEN catchment IN ('North West','Central West','Central Queensland') THEN 'Central'
            WHEN catchment IN ('Wide Bay','Sunshine Coast','Metro North','Metro South','Gold Coast') THEN 'South East'
            ELSE 'South West'
        END AS region
    FROM quarterly_format
        WHERE visit_type = 'General'
        GROUP BY quarter, catchment
    )

   
/*-- ___________________________________________________________________________

        Final Query: treatment rate + capacity percent
        + the catchment mean treatment ratio pulled in from catchment_totals is inclusive of waiting lists of 0
        + the clinic treatment ratio calculated here is not/ can not include empty waitlists.
     
                            
*/-- 
   SELECT
    cl.quarter, 
    cl.clinic_id,
    cl.clinic_name,
    -- clinic figures
        cl.clinic_waiting_total,
        cl.clinic_treated_total,
        -- clinic capacity snapshot, % of clinic treated
       ROUND(ROUND(cl.clinic_treated_total)/NULLIF(ROUND(cl.clinic_treated_total+cl.clinic_waiting_total),0),3)*100 AS clinic_capacity,
    -- clinic's pct of catchment
        ROUND(cl.clinic_waiting_total/NULLIF(ct.catchment_waiting_total, 0), 3) AS clinics_pct_of_catchment,
    -- per quarter, total (waiting+treated), clinic pct of qld
        ROUND(
            (cl.clinic_waiting_total + cl.clinic_treated_total)
            / NULLIF(SUM(cl.clinic_waiting_total + cl.clinic_treated_total) OVER (PARTITION BY cl.quarter), 0)
        , 4) AS clinic_pct_of_qld,
    -- catchment figures
        cl.catchment,
        ct.catchment_waiting_total,
        ct.catchment_treated_total,
    -- catchments pct of qld
        ROUND(SUM(cl.clinic_waiting_total) OVER (PARTITION BY cl.catchment, cl.quarter) 
             / SUM(cl.clinic_waiting_total) OVER (PARTITION BY cl.quarter), 4) AS catchment_pct_of_qld,
    -- region pct of qld
        ct.region,
        ROUND(SUM(cl.clinic_waiting_total) OVER (PARTITION BY ct.region, cl.quarter) 
             / SUM(cl.clinic_waiting_total) OVER (PARTITION BY cl.quarter), 4) AS region_pct_of_qld
    FROM clinic_totals cl
    JOIN catchment_totals ct ON cl.quarter = ct.quarter AND cl.catchment = ct.catchment
    WHERE cl.quarter >= '2023-04-01'
    GROUP BY cl.quarter, cl.clinic_id, cl.clinic_name, ct.region, cl.clinic_waiting_total, cl.clinic_treated_total,ct.mean_treatment_rate, cl.catchment, catchment_waiting_total, catchment_treated_total


