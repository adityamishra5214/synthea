{{ config(materialized='table') }}

/*
  mart_comorbidity_pairs
  Grain: One row per condition pair per cohort.
  Clinical Logic:
    - Filters to distinct patient diagnoses within each patient demographic cohort (60+ Elderly vs All Patients).
    - Performs an inner self-join on patient_id and cohort.
    - Uses strict inequality guard `condition_a < condition_b` to eliminate duplicates and reflexive self-pairs.
    - Computes patient count, cohort population denominator, prevalence percentage, and rank.
*/

WITH patient_cohorts AS (
    SELECT 
        patient_id,
        CASE 
            WHEN is_elderly_cohort_60plus THEN '60+ Elderly'
            ELSE 'Under 60'
        END AS cohort
    FROM {{ ref('dim_patients') }}
),

cohort_sizes AS (
    SELECT 
        cohort,
        COUNT(DISTINCT patient_id) AS total_cohort_patients
    FROM patient_cohorts
    GROUP BY cohort
),

patient_conditions AS (
    SELECT DISTINCT
        ipc.patient_id,
        pc.cohort,
        ipc.condition_description AS condition_name
    FROM {{ ref('int_patient_conditions') }} ipc
    JOIN patient_cohorts pc ON ipc.patient_id = pc.patient_id
),

condition_pairs AS (
    SELECT
        c1.cohort,
        c1.condition_name AS condition_a,
        c2.condition_name AS condition_b,
        COUNT(DISTINCT c1.patient_id) AS patient_count
    FROM patient_conditions c1
    JOIN patient_conditions c2 
      ON c1.patient_id = c2.patient_id
     AND c1.cohort = c2.cohort
     AND c1.condition_name < c2.condition_name
    GROUP BY
        c1.cohort,
        c1.condition_name,
        c2.condition_name
),

ranked_pairs AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['cp.cohort', 'cp.condition_a', 'cp.condition_b']) }} AS pair_id,
        cp.cohort,
        cp.condition_a,
        cp.condition_b,
        cp.patient_count,
        cs.total_cohort_patients,
        ROUND((cp.patient_count * 100.0) / cs.total_cohort_patients, 2) AS pct_of_cohort,
        DENSE_RANK() OVER (
            PARTITION BY cp.cohort 
            ORDER BY cp.patient_count DESC, cp.condition_a ASC, cp.condition_b ASC
        ) AS rank_in_cohort
    FROM condition_pairs cp
    JOIN cohort_sizes cs ON cp.cohort = cs.cohort
)

SELECT * FROM ranked_pairs
