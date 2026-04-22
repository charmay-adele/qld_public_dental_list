
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

        Level 1: calculate capacity ratios and percentages per quarter
                            
*/-- 

WITH clinic_totals AS (
        SELECT 
            quarter_start,
            SUM(total_treated) AS clinic_treated_total,
            SUM(total_waiting) AS clinic_waiting_total,
            clinic_id,
            clinic_name,
            catchment
    FROM quarterly_format
        WHERE visit_type = 'General'
        GROUP BY quarter_start, clinic_id, clinic_name, catchment
    ),
    catchment_totals AS (
     SELECT 
        quarter_start,
        SUM(total_treated)AS catchment_treated_total,
        SUM(total_waiting)AS catchment_waiting_total,
        catchment
    FROM quarterly_format
        WHERE visit_type = 'General'
        GROUP BY quarter_start, catchment
    )

/*----------------------------------------------------------------------------------------------*/
-- Capacity cannot be accurately measured without a waitlist to compare.                        --
-- This means clinics with zero waitlist are excluded from the distribution of capacity ratios, --
-- these valid observations are included in the overall catchment/system capacity ratios.       --
/*----------------------------------------------------------------------------------------------*/


/*-- ___________________________________________________________________________

        Final Query: clinic capacity
                quarter_start, 
                clinic_id, 
                clinic_name, 
                clinic_waiting_total, 
                clinic_treated_total, 
                catchment_total, 
                clinic_pct_of_catchment, 
                catchment, 
                capacity_ratio, 
                capacity_pct,
                quarters_to_treat, 
                months_to_treat
                            
                            
*/-- 

   SELECT
    cl.quarter_start, 
    cl.clinic_id,
    cl.clinic_name,
    -- clinic figures
        cl.clinic_waiting_total,
        cl.clinic_treated_total,
        -- clinic capacity ratio and percentage
        ROUND(cl.clinic_treated_total/NULLIF(cl.clinic_waiting_total,0), 3) AS clinic_capacity_ratio,
        ROUND((cl.clinic_treated_total/NULLIF(cl.clinic_waiting_total,0))*100, 2) AS clinic_capacity_pct,
        -- clinic quarter treated in months and quarters
       ROUND(1/NULLIF(ROUND(cl.clinic_treated_total/NULLIF(cl.clinic_waiting_total,0), 3),0),0) AS quarters_to_treat,
       ROUND((1/NULLIF(ROUND(cl.clinic_treated_total/NULLIF(cl.clinic_waiting_total,0), 3),0))*3, 0) AS months_to_treat,
    -- catchment figures
    cl.catchment,
    ct.catchment_waiting_total,
    ct.catchment_treated_total,
    -- clinic's pct of catchment
        ROUND(cl.clinic_waiting_total/ct.catchment_waiting_total, 3) AS clinics_pct_of_catchment
    FROM clinic_totals cl
    JOIN catchment_totals ct ON cl.quarter_start = ct.quarter_start AND cl.catchment = ct.catchment
    WHERE cl.clinic_waiting_total > 0
    GROUP BY cl.quarter_start, cl.clinic_id, cl.clinic_name, cl.clinic_waiting_total, cl.clinic_treated_total, cl.catchment, catchment_waiting_total, catchment_treated_total
    ORDER BY cl.quarter_start ASC;