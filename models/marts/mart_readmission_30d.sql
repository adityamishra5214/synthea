{{ config(materialized='table') }}

/*
  mart_readmission_30d
  Grain: One row per index inpatient admission.
  Clinical Logic:
    - Filters to inpatient encounters.
    - Uses LEAD() window function to find the subsequent inpatient admission for each patient.
    - Calculates days to readmission between index discharge date and next admission date.
    - Flags readmission when the next admission occurs within [0, 30] days of discharge.
*/

WITH inpatient_encounters AS (
    SELECT
        encounter_id AS index_encounter_id,
        patient_id,
        encounter_start_time AS index_admission_time,
        encounter_stop_time AS index_discharge_time,
        encounter_start_date AS index_admission_date,
        encounter_stop_date AS index_discharge_date,
        primary_condition,
        primary_condition_code,
        patient_gender,
        patient_age_band,
        patient_is_elderly_60plus,
        patient_city,
        patient_state,
        total_claim_cost AS index_encounter_cost,
        length_of_stay_days AS index_length_of_stay_days
    FROM {{ ref('fct_encounters') }}
    WHERE is_inpatient = TRUE
),

sequenced_admissions AS (
    SELECT
        *,
        LEAD(index_encounter_id) OVER (
            PARTITION BY patient_id 
            ORDER BY index_admission_time ASC
        ) AS readmit_encounter_id,
        LEAD(index_admission_date) OVER (
            PARTITION BY patient_id 
            ORDER BY index_admission_time ASC
        ) AS readmit_date,
        LEAD(primary_condition) OVER (
            PARTITION BY patient_id 
            ORDER BY index_admission_time ASC
        ) AS readmit_condition
    FROM inpatient_encounters
),

calculated_readmissions AS (
    SELECT
        index_encounter_id,
        patient_id,
        index_admission_date,
        index_discharge_date,
        readmit_encounter_id,
        readmit_date,
        readmit_condition,
        primary_condition,
        primary_condition_code,
        patient_gender,
        patient_age_band,
        patient_is_elderly_60plus,
        patient_city,
        patient_state,
        index_encounter_cost,
        index_length_of_stay_days,
        CASE
            WHEN readmit_date IS NOT NULL THEN DATE_DIFF('day', index_discharge_date, readmit_date)
            ELSE NULL
        END AS days_to_readmit,
        CASE
            WHEN readmit_date IS NOT NULL 
             AND DATE_DIFF('day', index_discharge_date, readmit_date) >= 0 
             AND DATE_DIFF('day', index_discharge_date, readmit_date) <= 30 THEN 1
            ELSE 0
        END AS readmit_flag
    FROM sequenced_admissions
)

SELECT * FROM calculated_readmissions
