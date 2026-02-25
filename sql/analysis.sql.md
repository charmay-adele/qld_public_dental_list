## Clinic Efficiency Analysis

The query below finds the average waiting time per clinic:

```sql
SELECT clinic_id, clinic_name,
       AVG(patients_waiting) AS avg_waiting
FROM Queue
GROUP BY clinic_id
ORDER BY avg_waiting DESC;




