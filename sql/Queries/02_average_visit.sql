
/*
Why collect an average of visit types across all quarters? 

Before investing time into each visit type, how is the system is weighted?
Let's see the scope of impact from differing appointment types.
With this information I can determine where to focus my analysis given any outliers.

*/

/*-- ___________________________________________________________________________

        Level 0: Set Up
                            + months to quarters
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


/*-- ___________________________________________________________________________

        Level 1: waitlist for each quarter x visit_type
                            + quarter
                            + type of visit
                            + waitlist
*/--

            WITH quarterly_visit_total AS (
                    SELECT
                        quarter_start AS quarter,
                        visit_type,
                        SUM(total_waiting) AS total_waitlist
                FROM quarterly_format
                GROUP BY quarter_start, visit_type
                )

/*-- ___________________________________________________________________________

        Final Query: average proportion of visit_types
                            
*/-- 

    SELECT -- average of those quarters
    visit_type,
    ROUND(AVG(qvt.total_waitlist),0) AS avg_visit_list,
    ROUND(
        AVG(qvt.total_waitlist)*100 -- partial figure
            /SUM(AVG(qvt.total_waitlist))OVER(), -- overall 
            2) AS pct_of_list
    FROM quarterly_visit_total qvt
    GROUP BY visit_type;
    