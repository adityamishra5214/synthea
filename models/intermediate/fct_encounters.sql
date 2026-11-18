WITH encounters AS (
    SELECT * FROM {{ ref('stg_encounters') }}
),

patients AS (
    SELECT 
        patient_id,
        gender,
        age_band,
        is_elderly_cohort_60plus,
        city,
        state
    FROM {{ ref('dim_patients') }}
),

encounter_conditions AS (
    -- Get primary condition recorded during the encounter if available
    SELECT
        encounter_id,
        condition_code,
        condition_description,
        ROW_NUMBER() OVER (PARTITION BY encounter_id ORDER BY condition_start_date ASC, condition_code ASC) AS cond_rank
    FROM {{ ref('stg_conditions') }}
),

primary_conditions AS (
    SELECT
        encounter_id,
        condition_code AS primary_condition_code,
        condition_description AS primary_condition_description
    FROM encounter_conditions
    WHERE cond_rank = 1
),

final AS (
    SELECT
        e.encounter_id,
        e.patient_id,
        e.encounter_start_time,
        e.encounter_stop_time,
        CAST(e.encounter_start_time AS DATE) AS encounter_start_date,
        CAST(e.encounter_stop_time AS DATE) AS encounter_stop_date,
        e.encounter_class,
        CASE WHEN e.encounter_class = 'inpatient' THEN TRUE ELSE FALSE END AS is_inpatient,
        CASE WHEN e.encounter_class = 'emergency' THEN TRUE ELSE FALSE END AS is_emergency,
        e.encounter_code,
        e.encounter_description,
        e.reason_code,
        e.reason_description,
        COALESCE(
            pc.primary_condition_description,
            e.reason_description,
            e.encounter_description,
            'Unspecified Diagnosis'
        ) AS primary_condition,
        COALESCE(
            pc.primary_condition_code,
            e.reason_code,
            e.encounter_code,
            'UNKNOWN'
        ) AS primary_condition_code,
        DATE_DIFF('minute', e.encounter_start_time, e.encounter_stop_time) AS length_of_stay_minutes,
        DATE_DIFF('day', CAST(e.encounter_start_time AS DATE), CAST(e.encounter_stop_time AS DATE)) AS length_of_stay_days,
        e.base_encounter_cost,
        e.total_claim_cost,
        e.payer_coverage,
        p.gender AS patient_gender,
        p.age_band AS patient_age_band,
        p.is_elderly_cohort_60plus AS patient_is_elderly_60plus,
        p.city AS patient_city,
        p.state AS patient_state
    FROM encounters e
    LEFT JOIN patients p ON e.patient_id = p.patient_id
    LEFT JOIN primary_conditions pc ON e.encounter_id = pc.encounter_id
)

SELECT * FROM final
