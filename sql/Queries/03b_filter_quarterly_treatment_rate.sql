/*    
    
    To first understand how 'Flow Efficiency' is measured, we need to understand the nature of the data.
    Waiting Patients are a snapshot, or a quarterly stocktake of patients waiting for an appointment. 
    Treated Patients are a flow, or the number of patients treated over a quarter period. 
    Information on patients who are new, or were waiting but cancelled is not available for this analysis. 
    
        Efficient flow of patients through the system appears as matching or exceeding waitlist demands.
        This way we can compare clinics, catchments and the system's efficiency via capacity or 
        the throughput of patients. This query compares capacity at a quarterly level, to produce a timeseries 
        analysis of system throughput.

        What is good flow efficiency? 

    The treatment ratio is calculated as:

        capacity_ratio = treated / waiting

    To express this as a percentage, we can multiply the capacity ratio by 100:

        capacity_pct = (treated / waiting) * 100

    To compliment these ratios, lets show the extent of the demand relative to the desired wait time. 
    By finding the number of quarters til completion of waitlist (at treatment rate) 
    and convert into months - multiplying those quarters by 3:

        total_months = (1/capacity_ratio) * 3
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
            SUM(patients_waiting) AS total_waiting   -- snapshot: extract sum across clinics on third monthly dates
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
    t.quarter_start,
    t.visit_type,
    t.clinic_id,
    t.clinic_name,
    t.catchment,
    t.total_treated AS treated,
    s.total_waiting AS waiting
FROM total_volume t
JOIN third_month_snapshot s
    ON  s.quarter_start = t.quarter_start
    AND s.clinic_id     = t.clinic_id
    AND s.visit_type    = t.visit_type
WHERE t.visit_type = 'General' 
    AND t.catchment <> 'Torres and Cape'
    AND t.catchment <> 'West Moreton';

/*-- ___________________________________________________________________________

        Level 1: calculate capacity ratios and percentages per quarter
                            
*/-- 

WITH quarter_capacity AS (
    SELECT
        quarter_start,
        SUM(waiting) AS waiting,
        SUM(treated) AS treated,
    -- clinic capacity ratio and percentage
        ROUND(SUM(treated)/NULLIF(SUM(waiting),0), 3) AS treatment_ratio
    FROM quarterly_format
    GROUP BY quarter_start
)

/*-- ___________________________________________________________________________

        Final Query: calculate number of months to complete the waitlist per quarter
                     metrics:
                            treatment_ratio     - treated/waiting       |
                            treament_pct_rate   - treatment ratio * 100  |
                            quarters_to_treat   - 1/capacity ratio      |
                            months_to_treat     - n_qtr_to_100pct * 3   |
                            
*/-- 

SELECT
    quarter_start,
    waiting,
    treated,
    treatment_ratio,
    ROUND(1/NULLIF(treatment_ratio, 0), 3) AS quarters_to_treat,
    ROUND((1/NULLIF(treatment_ratio, 0)) * 3, 2) AS months_to_treat
FROM quarter_capacity
WHERE quarter_start >= '2023-07-01'
ORDER BY quarter_start;


