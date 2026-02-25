-- {{ WAIT_PERIOD }} --
-- Wait_Period Schema: period_id, period_name, period_tier, period_description, 
--                     start_month, end_month, is_desired

-- for each period_tier there is an end month range that is infinite
-- here I have used (1000) for simplicity.

INSERT INTO wait_period 
(period_id, period_name, period_tier, period_description, start_month, end_month, is_desired)
VALUES
(101, 'D1', 'Immediate', '0–1 month', 0, 1, TRUE),
(102, 'D2', 'Short', '1–2 months', 1, 2, FALSE),
(103, 'D3', 'Moderate', '2–3 months', 2, 3, FALSE),
(104, 'D4', 'Extended', '3–4 months', 3, 4, FALSE),
(105, 'D5', 'Late', '4–5 months', 4, 5, FALSE),
(106, 'D6', 'Overdue', '5–6 months', 5, 1000, FALSE),
(201, 'D1', 'Immediate', '0–3 months', 0, 3, TRUE),
(202, 'D2', 'Short', '3–6 months', 3, 6, FALSE),
(203, 'D3', 'Moderate', '6–9 months', 6, 9, FALSE),
(204, 'D4', 'Extended', '9–12 months', 9, 12, FALSE),
(205, 'D5', 'Late', '12–15 months', 12, 15, FALSE),
(206, 'D6', 'Overdue', '15+ months', 15, 1000, FALSE),
(301, 'D1', 'Immediate', '0–6 months', 0, 6, TRUE),
(302, 'D2', 'Short', '6–12 months', 6, 12, TRUE),
(303, 'D3', 'Moderate', '12–18 months', 12, 18, FALSE),
(304, 'D4', 'Extended', '18–24 months', 18, 24, FALSE),
(305, 'D5', 'Late', '24–30 months', 24, 30, FALSE),
(306, 'D6', 'Overdue', '30+ months', 30, 1000, FALSE),
(401, 'D1', 'Immediate', '0–12 months', 0, 12, TRUE),
(402, 'D2', 'Short', '12–24 months', 12, 24, TRUE),
(403, 'D3', 'Moderate', '24–36 months', 24, 36, FALSE),
(404, 'D4', 'Extended', '36–48 months', 36, 48, FALSE),
(405, 'D5', 'Late', '48–60 months', 48, 60, FALSE),
(406, 'D6', 'Overdue', '60+ months', 60, 1000, FALSE);