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


-- Day 1 Part-to-Whole
        WITH quarterly_visit_total AS ( -- waitlist of each visit_type + quarter
        SELECT
        quarter_start AS quarter,
        SUM(total_waiting) AS total_waitlist,
        visit_type
    FROM quarterly_format
    GROUP BY quarter_start, visit_type
    )
    SELECT -- average of those quarters
    visit_type,
    ROUND(AVG(qvt.total_waitlist),0) AS avg_visit_list,
    ROUND(
        AVG(qvt.total_waitlist)*100 -- partial figure
            /SUM(AVG(qvt.total_waitlist))OVER(), -- define total figure
            2) AS pct_of_list
    FROM quarterly_visit_total qvt
    GROUP BY visit_type;

-- Day 2 Pictogram
        WITH clinic_totals AS (
        SELECT 
            quarter_start,
            SUM(total_waiting) AS clinic_waiting_total,
            SUM(total_treated) AS clinic_treated_total,
            clinic_id,
            clinic_name,
            catchment
    FROM quarterly_format
        WHERE visit_type = 'General'
        GROUP BY quarter_start, clinic_id, clinic_name, catchment
    )

    SELECT
    quarter_start,
    SUM(clinic_waiting_total) AS Catchment_total_waiting,
    SUM(clinic_treated_total) AS Catchment_total_treated,
    catchment,
        ROUND(SUM(clinic_treated_total)/NULLIF(SUM(clinic_waiting_total),0), 3) AS avg_capacity_ratio,
        ROUND((SUM(clinic_treated_total)/NULLIF(SUM(clinic_waiting_total),0))*100, 2) AS avg_capacity_pct,
        ROUND(1 / NULLIF((SUM(clinic_treated_total) / NULLIF(SUM(clinic_waiting_total),0)), 0),0) AS avg_n_qtr_to_100pct,
        3 * ROUND(1/NULLIF((SUM(clinic_treated_total) / NULLIF(SUM(clinic_waiting_total),0)),0),0) AS avg_total_months
    FROM clinic_totals
    WHERE quarter_start = '2025-04-01'
    GROUP BY quarter_start, catchment;

-- Day 3 Marimekko
    /*      Column width = avg general waitlist shared by catchment
            Segment height = avg general patient distribution in wait time. wait time profile
    */
    WITH qtrly_catchment_waitlist AS (
            SELECT
                quarter_start AS quarter,
                SUM(total_waiting) AS total_waitlist,
                catchment
            FROM quarterly_format
            WHERE visit_type = 'General'
            GROUP BY quarter_start, catchment
    )

    -- SELECT
    --     catchment,
    --     ROUND(AVG(total_waitlist),0) AS avg_waitlist,
    --     ROUND(AVG(total_waitlist)*100/SUM(AVG(total_waitlist))OVER(),2) AS avg_pct_of_waitlist
    -- FROM qtrly_catchment_waitlist
    -- GROUP BY catchment;

    /* now to aggregate by wait time profile*/

                DROP TABLE IF EXISTS waittime_profile_format;

                CREATE TEMPORARY TABLE waittime_profile_format AS
                    WITH profile_volume AS (
                            SELECT
                                date,
                                SUM(patients_waiting) AS patients_waiting,
                                SUM(patients_treated) AS patients_treated, 
                                wait_period.period_name AS wait_time_profile,
                                catchment
                                FROM queue
                                JOIN clinic ON clinic.clinic_id = queue.clinic_id
                                LEFT JOIN appointment_waitperiod ON appointment_waitperiod.period_id = queue.period_id
                                LEFT JOIN wait_period ON wait_period.period_id = appointment_waitperiod.period_id
                                WHERE queue.visit_id = 20 -- General category
                                GROUP BY date, clinic.catchment, wait_period.period_name
                        )
                        -- collapse to quarters, averaging sum of waiting per date. 
                            /*   months of quarters are averaged to maintain data integrity   */   
                    SELECT 
                        DATE_TRUNC('quarter', date)::date AS quarter_start,
                        ROUND(AVG(patients_waiting), 0) AS total_waiting,
                        ROUND(AVG(patients_treated), 0) AS total_treated,
                        wait_time_profile,
                        catchment
                    FROM profile_volume
                    GROUP BY quarter_start, catchment, wait_time_profile;


                    SELECT
                        ROUND(AVG(total_waiting), 0) AS avg_waittime_profile,
                        ROUND(
                            AVG(total_waiting) * 100 / NULLIF(SUM(AVG(total_waiting)) OVER (PARTITION BY catchment), 0),
                            2
                        ) AS avg_waittime_profile_pct,
                        wait_time_profile,
                        catchment
                    FROM waittime_profile_format
                    GROUP BY wait_time_profile, catchment
                    ORDER BY catchment, wait_time_profile;

        /* 
        Okay interesting, I have gotten to both categorisations of wait time profile and catchment.
        But I have separate queries for each. I want to combine them so I have the fields:
        catchment, wait_time_profile, avg_waittime_profile, avg_waittime_profile_pct, avg_pct_of_catchment_waitlist
                */
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
                            
                DROP TABLE IF EXISTS waittime_profile_format;

                CREATE TEMPORARY TABLE waittime_profile_format AS
                    WITH profile_volume AS (
                            SELECT
                                date,
                                SUM(patients_waiting) AS patients_waiting,
                                SUM(patients_treated) AS patients_treated, 
                                wait_period.period_name AS wait_time_profile,
                                catchment
                                FROM queue
                                JOIN clinic ON clinic.clinic_id = queue.clinic_id
                                LEFT JOIN appointment_waitperiod ON appointment_waitperiod.period_id = queue.period_id
                                LEFT JOIN wait_period ON wait_period.period_id = appointment_waitperiod.period_id
                                WHERE queue.visit_id = 20 -- General category
                                GROUP BY date, clinic.catchment, wait_period.period_name
                        )
                        -- collapse to quarters, averaging sum of waiting per date. 
                            /*   months of quarters are averaged to maintain data integrity   */   
                    SELECT 
                        DATE_TRUNC('quarter', date)::date AS quarter_start,
                        ROUND(AVG(patients_waiting), 0) AS total_waiting,
                        ROUND(AVG(patients_treated), 0) AS total_treated,
                        wait_time_profile,
                        catchment
                    FROM profile_volume
                    GROUP BY quarter_start, catchment, wait_time_profile;


        WITH qtrly_catchment_waitlist AS (
            SELECT
                catchment,
                AVG(total_waitlist) AS avg_catchment_waitlist  -- collapse to catchment only, no quarter
            FROM (
                SELECT quarter_start, catchment, SUM(total_waiting) AS total_waitlist
                FROM quarterly_format
                WHERE visit_type = 'General'
                GROUP BY quarter_start, catchment
            ) q
            GROUP BY catchment
        ),
        catchment_pct AS (
            SELECT
                catchment,
                avg_catchment_waitlist,
                ROUND(avg_catchment_waitlist * 100 / NULLIF(SUM(avg_catchment_waitlist) OVER (), 0), 2) AS avg_pct_of_waitlist
            FROM qtrly_catchment_waitlist
        ),
        profile_pct AS (
            SELECT
                wpf.wait_time_profile,
                wpf.catchment,
                ROUND(AVG(wpf.total_waiting), 0) AS avg_waittime_profile,
                ROUND(AVG(wpf.total_waiting) * 100 / NULLIF(SUM(AVG(wpf.total_waiting)) OVER (PARTITION BY wpf.catchment), 0), 2) AS avg_waittime_profile_pct
            FROM waittime_profile_format wpf
            GROUP BY wpf.wait_time_profile, wpf.catchment
        )
        SELECT
            pp.wait_time_profile,
            pp.catchment,
            pp.avg_waittime_profile,
            pp.avg_waittime_profile_pct,
            ROUND(cp.avg_catchment_waitlist, 0) AS avg_catchment_waitlist,
            cp.avg_pct_of_waitlist
        FROM profile_pct pp
        LEFT JOIN catchment_pct cp ON pp.catchment = cp.catchment
        ORDER BY pp.catchment, pp.wait_time_profile;

-- Day 4 Slope

-- Day 5 Experimental

-- Day 6 Reporters without Borders


-- Day 7 Multiscale

-- Day 8 Circular

-- Day 9 Wealth

-- Day 10 Pop Culture

-- Day 11 Physical