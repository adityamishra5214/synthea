WITH conditions AS (
    SELECT * FROM {{ ref('stg_conditions') }}
),

patients AS (
    SELECT 
        patient_id,
        gender,
        age_band,
        is_elderly_cohort_60plus
    FROM {{ ref('dim_patients') }}
),

aggregated AS (
    SELECT
        c.patient_id,
        c.condition_description,
        c.condition_code,
        MIN(c.condition_start_date) AS first_diagnosis_date,
        MAX(COALESCE(c.condition_stop_date, CURRENT_DATE)) AS last_active_date,
        MAX(CASE WHEN c.is_active_condition THEN 1 ELSE 0 END) = 1 AS is_currently_active,
        p.gender,
        p.age_band,
        p.is_elderly_cohort_60plus
    FROM conditions c
    JOIN patients p ON c.patient_id = p.patient_id
    GROUP BY
        c.patient_id,
        c.condition_description,
        c.condition_code,
        p.gender,
        p.age_band,
        p.is_elderly_cohort_60plus
)

SELECT * FROM aggregated
