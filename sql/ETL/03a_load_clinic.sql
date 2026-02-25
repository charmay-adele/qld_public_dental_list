

-- [TRANSFORM] 
-- [LOAD]
-- filter for distinct values of clinicID (col2) to load into 'clinic' table
-- Doing this first ensures 'clinic' table is populated with unique clinic IDs 
-- as a reference before loading other related tables.
-- Add only new values not already listed, to avoid duplicates from an updated csv file.

INSERT INTO Clinic (clinic_id)
SELECT DISTINCT clinicID
FROM stage_raw
WHERE clinicID IS NOT NULL
AND clinicID NOT IN (SELECT clinic_id FROM Clinic);

-- Now 'clinic' table has clinic_id column full of unique ID values.
-- Lets populate the other columns: catchment & clinic_name pertaining to each clinic_id
-- This will need UPDATE to change existing (NULL) values in specifics rows and columns based 
-- on specific conditions (ie matching clinic_id). This is different from INSERT which adds new rows.
-- or ALTER which changes table structure.

-- [ UPDATE Clinic Table ] --
UPDATE clinic
SET clinic_name = sr.clinicName,
    catchment = sr."Hospital and Health Service"
FROM stage_raw AS sr
WHERE clinic.clinic_id = sr.clinicID;

-- Verify data loaded correctly
SELECT * FROM clinic LIMIT 5;  -- Preview first 5 rows of the Clinic table
