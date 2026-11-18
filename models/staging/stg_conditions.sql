WITH source AS (
    SELECT * FROM {{ source('raw', 'conditions') }}
),

renamed_and_cast AS (
    SELECT
        CAST(PATIENT AS VARCHAR) AS patient_id,
        CAST(ENCOUNTER AS VARCHAR) AS encounter_id,
        TRY_CAST(NULLIF(START, '') AS DATE) AS condition_start_date,
        TRY_CAST(NULLIF(STOP, '') AS DATE) AS condition_stop_date,
        CASE 
            WHEN NULLIF(STOP, '') IS NULL THEN TRUE 
            ELSE FALSE 
        END AS is_active_condition,
        NULLIF(CODE, '') AS condition_code,
        TRIM(DESCRIPTION) AS condition_description
    FROM source
    WHERE PATIENT IS NOT NULL 
      AND CODE IS NOT NULL 
      AND START IS NOT NULL
),

with_surrogate_key AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key([
            'patient_id',
            'encounter_id',
            'condition_code',
            'condition_start_date'
        ]) }} AS condition_id,
        patient_id,
        encounter_id,
        condition_start_date,
        condition_stop_date,
        is_active_condition,
        condition_code,
        condition_description
    FROM renamed_and_cast
)

SELECT *
FROM with_surrogate_key
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY condition_id 
    ORDER BY condition_stop_date
) = 1
