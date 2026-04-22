
----------------------------------------------------------------------------------------------------------------------------
-- Flow Efficiency --
----------------------------------------------------------------------------------------------------------------------------

/*
    To first understand how 'Flow Efficiency' is measured, we need to understand the nature of the data.
    Waiting Patients are a snapshot, or stocktake of the number of patients waiting for an appointment
    at a given point of time quarterly. Treated Patients are a flow, or the number of patients treated over a 
    quarter period. Information on patients who are new, or were waiting but cancelled is not available
    for this analysis. 

    Efficient flow of patients through the system appears as matching or exceeding waitlist demands.
    A way to compare clinics, catchments and the systems efficiency is through capacity or 
    throughput of patients. To do this the following metrics are calculated for general appointment types:

    The capacity ratio is calculated as:
    capacity_ratio = treated / waiting

    To express this as a percentage, we can multiply the capacity ratio by 100:
    capacity_pct = (treated / waiting) * 100

    Additionally, we can estimate the number of quarters it would take for a clinic to clear its waitlist at its current treatment rate:
    n_qtr_to_100pct = 1 / capacity_ratio

    To show the extent of the demand relative to a threshold of 12-24months (General's desired wait time).
    Quarters are converted into months, multiply by 3:
    total_months = n_qtr_to_100pct * 3
*/

--| capacity of general appointment visits across clinics and catchments |--
            /*                                           /*
                flow efficiency metrics:
                capacity_ratio  - treated/waiting       |
                capacity_pct    - capacity ratio * 100  |
                n_qtr_to_100pct - 1/capacity ratio      |
                total_months    - n_qtr_to_100pct * 3   |
            */                                          */


/* Formatting Dates */

-- Set up frequency -- months -> quarters

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
                ROUND(AVG(patients_treated), 0) AS total_treated,
                clinic_id,
                clinic_name,
                catchment
            FROM total_volume
            GROUP BY quarter_start, visit_type, clinic_id, clinic_name, catchment;


/* Flow Efficiency | Capacity Metrics */

-- Clinic Capacity: quarter, clinic_name, clinic & catchment totals, capacity ratio and percentage.
    /* Per Clinic: capacity_ratio/pct need waitlists of > 0 apart of the distribution */

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
    ),

/*----------------------------------------------------------------------------------------------*/
-- Capacity cannot be accurately measured without a waitlist to compare.                        --
-- This means clinics with zero waitlist are excluded from the distribution of capacity ratios, --
-- these valid observations are included in the overall catchment/system capacity ratios.       --
/*----------------------------------------------------------------------------------------------*/

clinic_capacity AS (
    SELECT
        quarter_start,
        catchment,
        clinic_name,
        clinic_waiting_total,
        clinic_treated_total,
        clinic_treated_total / NULLIF(clinic_waiting_total, 0) AS capacity_ratio
    FROM clinic_totals
    WHERE clinic_waiting_total > 0
)
-- Catchment Capacity: quarter, catchment, average_capacity, median_capacity
catchment_capacity AS(
    SELECT
        ct.quarter_start,
        ct.catchment,
        ROUND(ct.catchment_treated_total/NULLIF(ct.catchment_waiting_total,0),2)                  AS mean_capacity_ratio,
        ROUND((ct.catchment_treated_total/NULLIF(ct.catchment_waiting_total,0))*100, 2)           AS mean_capacity_pct,
        ROUND(CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY (capacity_ratio, 0)
            )AS NUMERIC),3)                                                                       AS median_capacity_ratio,
            -- each clinic's ratio is in order, take the 50th percentile - aka median
        ROUND(
            CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY (capacity_ratio, 0))*100 -- capacity percentage per clinic
            ) AS NUMERIC, 2)                                                                     AS median_capacity_pct
            -- make that a percentage
    FROM catchment_totals ct
    JOIN clinic_capacity cl ON ct.quarter_start = cl.quarter_start AND ct.catchment = cl.catchment
    WHERE ct.catchment_waiting_total > 0
    GROUP BY ct.quarter_start, ct.catchment, ct.catchment_treated_total, 
             ct.catchment_waiting_total
    ORDER BY ct.quarter_start, ct.catchment
),

difference_from_median AS (
    SELECT
        cc.quarter_start,
        cc.clinic_name,
        cc.catchment,
        ABS(cc.median_capacity_ratio - (cl.clinic_treated_total / NULLIF(cl.clinic_waiting_total, 0))) AS median_diff_deviation,
        -- next step percentile 0.5 median diff deviation
        ABS(cc.mean_capacity_ratio - cc.median_capacity_ratio) AS mean_median_difference
    FROM catchment_capacity cc
    JOIN clinic_totals cl ON cc.quarter_start = cl.quarter_start
                         AND cc.catchment = cl.catchment
                         AND cc.clinic_name = cl.clinic_name
)


SELECT 
cc.quarter_start,
cc.catchment,
cc.mean_capacity_ratio AS mean_capacity_ratio,
cc.mean_capacity_pct AS mean_capacity_pct,
-- standard deviation of clinic capacity ratios within catchment
ROUND(STDDEV_POP(capacity_ratio, 0), 3) AS stddev_capacity_ratio,
cc.median_capacity_ratio,
cc.median_capacity_pct,
-- median absolute deviation of clinic capacity ratios within catchment
ROUND(CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY d.median_diff_deviation) AS NUMERIC), 6) AS mad_capacity_ratio
FROM catchment_capacity cc
JOIN difference_from_median d ON cc.quarter_start = d.quarter_start 
                             AND cc.clinic_name = d.clinic_name 
                             AND cc.catchment = d.catchment
JOIN clinic_capacity cl       ON cl.quarter_start = cc.quarter_start
                             AND cl.catchment = cc.catchment
GROUP BY cc.quarter_start, cc.catchment, 
         cc.mean_capacity_ratio, cc.mean_capacity_pct,
         cc.median_capacity_ratio, cc.median_capacity_pct
ORDER BY cc.quarter_start, cc.catchment;



-- note: need to check on catchments waiting list summing to 0? this is wrong. check catchment ctes etc.
/*
        - the problem was catchment_totals were grouped by clinics
        - stddev was 0 across all clinic deviations from the mean 
          because I wrongly put catchment down (not clinics)
*/
-- mean is per catchment
/*
          need to double check goals behind mean? 
          or think about why median is different across
          clincs while mean is per catchment
*/


-- what do I want?
/*


avg_catchment_capacity - (catchment)
stddev of clinics per catchment - (catchment)
median_catchment_capacity - (catchment)
median absolute deviation of clinics per catchment - (catchment)


*/





/* Clinic Capacity */
   SELECT
    cl.quarter_start, 
    cl.clinic_id,
    -- clinic figures
        cl.clinic_waiting_total,
        cl.clinic_treated_total,
    -- catchment figures
        cl.catchment,
        catchment_waiting_total,
        catchment_treated_total,
    -- cumulative catchment total for quarter
        SUM(cl.clinic_waiting_total)OVER(PARTITION BY cl.catchment, cl.quarter_start ORDER BY cl.quarter_start) AS catchment_total,
    -- clinic capacity ratio and percentage
        ROUND(cl.clinic_treated_total/NULLIF(cl.clinic_waiting_total,0), 3) AS capacity_ratio,
        ROUND((cl.clinic_treated_total/NULLIF(cl.clinic_waiting_total,0))*100, 2) AS capacity_pct
    FROM clinic_totals cl
    JOIN catchment_totals ct ON cl.quarter_start = ct.quarter_start AND cl.catchment = ct.catchment
    WHERE cl.clinic_waiting_total > 0
    GROUP BY cl.quarter_start, cl.clinic_id, cl.clinic_waiting_total, cl.clinic_treated_total, cl.catchment, catchment_waiting_total, catchment_treated_total
    ORDER BY cl.clinic_waiting_total ASC;

-- Quarterly System Capacity: quarter, system treated/waiting totals, system capacity ratio and percentage. 
    WITH catchment_totals AS (
            SELECT 
                quarter_start,
                SUM(total_treated) AS catchment_treated_total,
                SUM(total_waiting) AS catchment_waiting_total,
                catchment
        FROM quarterly_format
            WHERE visit_type = 'General'
            GROUP BY quarter_start, catchment
        )

    SELECT
        ct.quarter_start,
        SUM(ct.catchment_treated_total) AS system_treated_total,
        SUM(ct.catchment_waiting_total) AS system_waiting_total,
        ROUND(
            AVG(
                SUM(ct.catchment_treated_total)/SUM(ct.catchment_waiting_total)
                )OVER(
                PARTITION BY ct.quarter_start 
                ORDER BY ct.quarter_start)
                , 4) AS system_capacity_ratio,
        ROUND(
            AVG(
                SUM(ct.catchment_treated_total)/SUM(ct.catchment_waiting_total)
                )OVER(
                PARTITION BY ct.quarter_start 
                ORDER BY ct.quarter_start) * 100
                , 2) AS system_capacity_pct
    FROM catchment_totals ct
    GROUP BY ct.quarter_start;


----------------------------------------------------------------------------------------------------------------------------
-- Homogeneity --
----------------------------------------------------------------------------------------------------------------------------

-- Standard Deviation


-- Median Absolute Deviation

-- 1. Find the Median of the dataset.
-- 2. Calculate the absolute difference between each data point and that median.
-- 3. Find the Median of those absolute differences. 

*/