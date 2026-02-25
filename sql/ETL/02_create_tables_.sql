-- Schema for Waiting List Database

CREATE TABLE clinic (
    clinic_id INT PRIMARY KEY,  -- Unique identifier for each clinic
    catchment VARCHAR(255),     -- Area served by the clinic
    clinic_name VARCHAR(255)    -- Name of the clinic
);

CREATE TABLE appointment (
    visit_id INT PRIMARY KEY,   -- Unique identifier for each appointment
    visit_type VARCHAR(255),    -- type of appointment
    schedule INT                -- desired wait in months
);

CREATE TABLE wait_period (
    period_id INT PRIMARY KEY, -- Unique identifier for each wait period
    period_name VARCHAR(255),      -- Name of the wait period (D1, D2, etc.))
    period_tier VARCHAR(255),      -- wait period Tier classification (immediate,short..)
    period_description VARCHAR(255), -- Description of the wait period (e.g., "0-1 month")
    start_month INT,           -- Start month of the wait period
    end_month INT,              -- End month of the wait period
    is_desired BOOLEAN         -- Indicates if this wait period is considered desired
);


CREATE TABLE appointment_waitperiod (
    visit_id INT,              -- Foreign key referencing Appointment
    period_id INT,             -- Foreign key referencing Wait_Period
    PRIMARY KEY (visit_id, period_id),
    FOREIGN KEY (visit_id) REFERENCES Appointment(visit_id),
    FOREIGN KEY (period_id) REFERENCES Wait_Period(period_id)
);

CREATE TABLE queue (
    log_id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY, -- Unique identifier for each log entry
    date DATE,                 -- Date of the log entry  
    clinic_id INT,             -- Foreign key referencing Clinic
    visit_id INT,              -- Foreign key referencing Appointment
    period_id INT,             -- Foreign key referencing Wait_Period
    patients_waiting INT,      -- Number of patients waiting
    patients_treated INT,      -- Number of patients treated
    FOREIGN KEY (clinic_id) REFERENCES Clinic(clinic_id),
    FOREIGN KEY (visit_id) REFERENCES Appointment(visit_id),
    FOREIGN KEY (period_id) REFERENCES Wait_Period(period_id)
);


-------------------------------------------
/*              TOOL TABLES              */
-------------------------------------------

CREATE TABLE dim_date (
    date_id SERIAL PRIMARY KEY,  -- Unique identifier for each date
    date DATE UNIQUE,            -- Actual date
    day INT,                     -- Day of the month
    month INT,                   -- Month of the year
    year INT,                    -- Year
    quarter INT,                 -- Quarter of the year
    day_of_week INT,             -- Day of the week (1-7)
    is_weekend BOOLEAN           -- Indicates if the date falls on a weekend
);
