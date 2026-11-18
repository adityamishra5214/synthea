{{ config(materialized='table') }}

/*
  mart_chronic_adherence
  Grain: One row per patient per chronic condition.
  Clinical Logic:
    - Identifies target chronic condition cohorts (Diabetes, Hypertension).
    - Captures the initial diagnosis date for each patient.
    - Evaluates longitudinal medication therapy exposure up to patient death or study cutoff date.
    - Computes adherence_proxy: proportion of time covered by therapy since diagnosis.
    - Computes gap_days: unmedicated days during the post-diagnosis disease duration.
    - Computes active_med_flag: whether patient has an active prescription at the close of observation.
    - Note: This represents an observational proxy metric derived from synthetic prescription intervals.
*/

WITH dataset_cutoff AS (
    SELECT CAST(MAX(encounter_start_time) AS DATE) AS max_dataset_date
    FROM {{ ref('stg_encounters') }}
),

chronic_diagnoses AS (
    SELECT
        c.patient_id,
        CASE
            WHEN LOWER(c.condition_description) LIKE '%diabetes%' THEN 'Diabetes'
            WHEN LOWER(c.condition_description) LIKE '%hypertension%' THEN 'Hypertension'
        END AS condition,
        MIN(c.condition_start_date) AS diagnosis_date
    FROM {{ ref('stg_conditions') }} c
    WHERE LOWER(c.condition_description) LIKE '%diabetes%'
       OR LOWER(c.condition_description) LIKE '%hypertension%'
    GROUP BY
        c.patient_id,
        CASE
            WHEN LOWER(c.condition_description) LIKE '%diabetes%' THEN 'Diabetes'
            WHEN LOWER(c.condition_description) LIKE '%hypertension%' THEN 'Hypertension'
        END
),

patients AS (
    SELECT
        p.patient_id,
        p.gender,
        p.age_band,
        p.death_date,
        p.is_deceased
    FROM {{ ref('dim_patients') }} p
),

cohort_base AS (
    SELECT
        cd.patient_id,
        cd.condition,
        cd.diagnosis_date,
        p.gender,
        p.age_band,
        p.death_date,
        p.is_deceased,
        COALESCE(p.death_date, dc.max_dataset_date) AS observation_end_date,
        GREATEST(1, DATE_DIFF('day', cd.diagnosis_date, COALESCE(p.death_date, dc.max_dataset_date))) AS days_since_diagnosis,
        GREATEST(1, DATE_DIFF('month', cd.diagnosis_date, COALESCE(p.death_date, dc.max_dataset_date))) AS months_since_diagnosis
    FROM chronic_diagnoses cd
    JOIN patients p ON cd.patient_id = p.patient_id
    CROSS JOIN dataset_cutoff dc
),

medication_exposure AS (
    SELECT
        m.patient_id,
        CASE
            WHEN LOWER(m.reason_description) LIKE '%diabet%' 
              OR LOWER(m.medication_description) LIKE '%metformin%' 
              OR LOWER(m.medication_description) LIKE '%insulin%' THEN 'Diabetes'
            WHEN LOWER(m.reason_description) LIKE '%hypertens%' 
              OR LOWER(m.medication_description) LIKE '%lisinopril%' 
              OR LOWER(m.medication_description) LIKE '%hydrochlorothiazide%' 
              OR LOWER(m.medication_description) LIKE '%amlodipine%' 
              OR LOWER(m.medication_description) LIKE '%atenolol%' THEN 'Hypertension'
        END AS condition,
        m.medication_start_date,
        COALESCE(m.medication_stop_date, dc.max_dataset_date) AS medication_stop_date
    FROM {{ ref('stg_medications') }} m
    CROSS JOIN dataset_cutoff dc
    WHERE LOWER(m.reason_description) LIKE '%diabet%' 
       OR LOWER(m.reason_description) LIKE '%hypertens%'
       OR LOWER(m.medication_description) LIKE '%metformin%'
       OR LOWER(m.medication_description) LIKE '%insulin%'
       OR LOWER(m.medication_description) LIKE '%lisinopril%'
       OR LOWER(m.medication_description) LIKE '%hydrochlorothiazide%'
       OR LOWER(m.medication_description) LIKE '%amlodipine%'
       OR LOWER(m.medication_description) LIKE '%atenolol%'
),

patient_therapy_metrics AS (
    SELECT
        cb.patient_id,
        cb.condition,
        cb.diagnosis_date,
        cb.observation_end_date,
        cb.days_since_diagnosis,
        cb.months_since_diagnosis,
        cb.gender,
        cb.age_band,
        COUNT(me.medication_start_date) AS total_prescriptions_count,
        MAX(CASE WHEN me.medication_stop_date >= cb.observation_end_date THEN 1 ELSE 0 END) AS active_med_flag,
        COALESCE(
            SUM(
                GREATEST(0, DATE_DIFF('day', 
                    GREATEST(me.medication_start_date, cb.diagnosis_date), 
                    LEAST(me.medication_stop_date, cb.observation_end_date)
                ))
            ),
            0
        ) AS total_covered_days
    FROM cohort_base cb
    LEFT JOIN medication_exposure me
      ON cb.patient_id = me.patient_id
     AND cb.condition = me.condition
     AND me.medication_stop_date >= cb.diagnosis_date
    GROUP BY
        cb.patient_id,
        cb.condition,
        cb.diagnosis_date,
        cb.observation_end_date,
        cb.days_since_diagnosis,
        cb.months_since_diagnosis,
        cb.gender,
        cb.age_band
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['patient_id', 'condition']) }} AS adherence_id,
        patient_id,
        condition,
        gender,
        age_band,
        diagnosis_date,
        observation_end_date,
        days_since_diagnosis,
        months_since_diagnosis,
        total_prescriptions_count,
        active_med_flag,
        GREATEST(0, days_since_diagnosis - total_covered_days) AS gap_days,
        ROUND(LEAST(1.0, total_covered_days * 1.0 / days_since_diagnosis), 4) AS adherence_proxy,
        CASE
            WHEN (LEAST(1.0, total_covered_days * 1.0 / days_since_diagnosis)) >= 0.80 THEN 'High Adherence (>=80%)'
            WHEN (LEAST(1.0, total_covered_days * 1.0 / days_since_diagnosis)) >= 0.50 THEN 'Moderate Adherence (50-79%)'
            ELSE 'Low / Gapped (<50%)'
        END AS adherence_category
    FROM patient_therapy_metrics
)

SELECT * FROM final
