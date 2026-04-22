/*    
    
    To first understand how 'Flow Efficiency' is measured, we need to understand the nature of the data.
    Waiting Patients are a snapshot, or a quarterly stocktake of patients waiting for an appointment. 
    Treated Patients are a flow, or the number of patients treated over a quarter period. 
    Information on patients who are new, or were waiting but cancelled is not available for this analysis. 
    
    Efficient flow of patients through the system appears as matching or exceeding waitlist demands.
    This way we can compare clinics, catchments and the system's efficiency via capacity or 
    the throughput of patients. This query compares capacity at a quarterly level, to produce a timeseries 
    analysis of system throughput.

    The capacity ratio is calculated as:

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
*/--

DROP TABLE IF EXISTS quarterly_format;

        CREATE TEMPORARY TABLE quarterly_format AS
            WITH total_volume AS (
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
                -- collapse to quarters, averaging sum of waiting per date. 
                    /*   months of quarters are averaged to maintain data integrity   */   
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

WITH total_quarter AS (
    SELECT
        quarter_start,
        SUM(total_waiting) AS waiting,
        SUM(total_treated) AS treated
FROM quarterly_format
GROUP BY quarter_start
ORDER BY quarter_start
),

/*-- ___________________________________________________________________________

        Level 1: calculate capacity ratios and percentages per quarter
                            
*/-- 

quarter_capacity AS (
    SELECT
        quarter_start,
        waiting,
        treated,
    -- clinic capacity ratio and percentage
        ROUND(treated/NULLIF(waiting,0), 3) AS capacity_ratio,
        ROUND((treated/NULLIF(waiting,0))*100, 2) AS capacity_pct
    FROM total_quarter
)

/*-- ___________________________________________________________________________

        Final Query: calculate number of months to complete the waitlist per quarter
                     metrics:
                            capacity_ratio  - treated/waiting       |
                            capacity_pct    - capacity ratio * 100  |
                            n_qtr_to_100pct - 1/capacity ratio      |
                            total_months    - n_qtr_to_100pct * 3   |
                            
*/-- 

SELECT
    quarter_start,
    waiting,
    treated,
    capacity_ratio AS treatment_rate,
    capacity_pct AS percentage_treated,
    ROUND(1/NULLIF(capacity_ratio, 0), 3) AS quarters_to_treat,
    ROUND((1/NULLIF(capacity_ratio, 0)) * 3, 2) AS months_to_treat
FROM quarter_capacity
ORDER BY quarter_start
