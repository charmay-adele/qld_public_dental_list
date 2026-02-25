
-- {{ APPOINTMENT }} --
-- Appointment Schema: visit_id, period_id, visit_type, schedule
-- INSERT Manual data entry using Queensland Dental Waiting List data info tab.

-- visit_id is an arbitrary unique identifier for each appointment type.
-- visit_type is the type of appointment as per source data.
-- schedule is the expected wait time in months for that appointment type, 
-- pulled from appointment descriptions in the source data.


INSERT INTO appointment (visit_id, visit_type, schedule) VALUES
(10,'Clinical Assessment', 1),
(20,'General', 24),
(30,'Priority 1', 1),
(40,'Priority 2', 3),
(50,'Priority 3', 12),
(60,'General Anaesthetic Category 1', 1),
(70,'General Anaesthetic Category 2', 3),
(80,'General Anaesthetic Category 3', 12);

