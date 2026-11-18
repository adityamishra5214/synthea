WITH patients AS (
    SELECT * FROM {{ ref('stg_patients') }}
),

patient_conditions AS (
    SELECT
        patient_id,
        COUNT(DISTINCT condition_id) AS total_conditions_diagnosed,
        MAX(CASE WHEN LOWER(condition_description) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
        MAX(CASE WHEN LOWER(condition_description) LIKE '%hypertension%' THEN 1 ELSE 0 END) AS has_hypertension,
        MAX(CASE WHEN LOWER(condition_description) LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) AS has_chronic_kidney_disease,
        MAX(CASE WHEN LOWER(condition_description) LIKE '%coronary heart disease%' OR LOWER(condition_description) LIKE '%ischemic heart disease%' THEN 1 ELSE 0 END) AS has_cardiovascular_disease
    FROM {{ ref('stg_conditions') }}
    GROUP BY patient_id
),

patient_encounters AS (
    SELECT
        patient_id,
        COUNT(DISTINCT encounter_id) AS total_encounters_count,
        MIN(encounter_start_time) AS first_encounter_time,
        MAX(encounter_start_time) AS last_encounter_time
    FROM {{ ref('stg_encounters') }}
    GROUP BY patient_id
),

joined AS (
    SELECT
        p.patient_id,
        p.first_name,
        p.last_name,
        CONCAT_WS(' ', p.first_name, p.last_name) AS full_name,
        p.gender,
        p.race,
        p.ethnicity,
        p.birth_date,
        p.death_date,
        p.is_deceased,
        CASE 
            WHEN p.death_date IS NOT NULL THEN DATE_DIFF('year', p.birth_date, p.death_date)
            ELSE DATE_DIFF('year', p.birth_date, CURRENT_DATE)
        END AS current_or_exit_age,
        CASE
            WHEN (CASE WHEN p.death_date IS NOT NULL THEN DATE_DIFF('year', p.birth_date, p.death_date) ELSE DATE_DIFF('year', p.birth_date, CURRENT_DATE) END) < 18 THEN '0-17 Pediatric'
            WHEN (CASE WHEN p.death_date IS NOT NULL THEN DATE_DIFF('year', p.birth_date, p.death_date) ELSE DATE_DIFF('year', p.birth_date, CURRENT_DATE) END) BETWEEN 18 AND 49 THEN '18-49 Adult'
            WHEN (CASE WHEN p.death_date IS NOT NULL THEN DATE_DIFF('year', p.birth_date, p.death_date) ELSE DATE_DIFF('year', p.birth_date, CURRENT_DATE) END) BETWEEN 50 AND 64 THEN '50-64 Middle-Aged'
            ELSE '65+ Senior'
        END AS age_band,
        CASE
            WHEN (CASE WHEN p.death_date IS NOT NULL THEN DATE_DIFF('year', p.birth_date, p.death_date) ELSE DATE_DIFF('year', p.birth_date, CURRENT_DATE) END) >= 60 THEN TRUE
            ELSE FALSE
        END AS is_elderly_cohort_60plus,
        p.city,
        p.state,
        p.county,
        p.zip_code,
        p.healthcare_expenses,
        p.healthcare_coverage,
        COALESCE(c.total_conditions_diagnosed, 0) AS total_conditions_diagnosed,
        COALESCE(c.has_diabetes, 0) = 1 AS has_diabetes,
        COALESCE(c.has_hypertension, 0) = 1 AS has_hypertension,
        COALESCE(c.has_chronic_kidney_disease, 0) = 1 AS has_chronic_kidney_disease,
        COALESCE(c.has_cardiovascular_disease, 0) = 1 AS has_cardiovascular_disease,
        COALESCE(e.total_encounters_count, 0) AS total_encounters_count,
        e.first_encounter_time,
        e.last_encounter_time
    FROM patients p
    LEFT JOIN patient_conditions c ON p.patient_id = c.patient_id
    LEFT JOIN patient_encounters e ON p.patient_id = e.patient_id
)

SELECT * FROM joined
