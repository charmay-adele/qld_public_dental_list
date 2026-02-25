
-- Create a temporary staging table to hold raw CSV data with all columns available for smooth loading

CREATE TEMP TABLE IF NOT EXISTS stage_raw (
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

\copy stage_raw  FROM 'data/processed/master_dataset.csv' WITH (FORMAT CSV, HEADER TRUE, NULL '-');