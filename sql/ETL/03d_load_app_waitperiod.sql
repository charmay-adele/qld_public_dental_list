
-- {{ APPOINTMENT_WAITPERIOD }} --
-- a junction table to link Appointment and Wait_Period
-- via foreign key
INSERT INTO appointment_waitperiod (visit_id, period_id) VALUES
(10,101),(10,102),(10,103),(10,104),(10,105), -- Clinical Assessment
(30,101),(30,102),(30,103),(30,104),(30,105), -- Priority 1
(60,101),(60,102),(60,103),(60,104),(60,105), -- General Anaesthetic Category 1
(40,201),(40,202),(40,203),(40,204),(40,205), -- Priority 2
(70,201),(70,202),(70,203),(70,204),(70,205), -- General Anaesthetic Category 2
(50,301),(50,302),(50,303),(50,304),(50,305), -- Priority 3
(80,301),(80,302),(80,303),(80,304),(80,305), -- General Anaesthetic Category 3
(20,401),(20,402),(20,403),(20,404),(20,405) -- General
;