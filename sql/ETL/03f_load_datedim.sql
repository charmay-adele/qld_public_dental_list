CREATE TEMP TABLE stage_raw (
    date DATE, --- date
    clinicID INT, --- clinicID
    clinicName VARCHAR(255), --- clinicName
    "Hospital and Health Service" VARCHAR(255), --- Hospital and Health Service
    Area TEXT, --- Area
    "Waiting D1" INT,
    "Waiting D2" INT,
    "Waiting D3" INT,
    "Waiting D4" INT,
    "Waiting D5" INT,
    "Waiting D6" INT,
    "Waiting D7" INT,
    "Treated D1" INT,
    "Treated D2" INT,
    "Treated D3" INT,
    "Treated D4" INT,
    "Treated D5" INT,
    "Treated D6" INT,
    "Treated D7" INT
);

-- Load data from CSV into the staging raw table
COPY stage_raw
-- FROM 'F:/Git/projects/waiting_list/data/processed/master_dataset.csv'
FROM '/Users/charmay/Analyst_Portfolio/qld_public_dental_list/data/processed/master_dataset.csv'
WITH (FORMAT CSV, null "-", HEADER TRUE, DELIMITER ',');


-- {{ DIM_DATE }} --
INSERT INTO dim_date (date, month, year, quarter)
SELECT
    d::date AS date,
    EXTRACT(MONTH FROM d) AS month,
    EXTRACT(YEAR FROM d) AS year,
    EXTRACT(QUARTER FROM d) AS quarter
FROM generate_series(
    '2020-01-01'::date,
    (SELECT MAX(date) FROM stage_raw),  -- or queue table
    '1 day'::interval
) AS d
ON CONFLICT (date) DO NOTHING;




SELECT * FROM queue LIMIT 10;
SELECT * FROM appointment_waitperiod LIMIT 10;
SELECT * FROM clinic LIMIT 10;
SELECT * FROM appointment LIMIT 10;