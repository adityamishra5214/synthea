WITH source AS (
    SELECT * FROM {{ source('raw', 'medications') }}
),

renamed_and_cast AS (
    SELECT
        CAST(PATIENT AS VARCHAR) AS patient_id,
        CAST(ENCOUNTER AS VARCHAR) AS encounter_id,
        NULLIF(PAYER, '') AS payer_id,
        TRY_CAST(NULLIF(START, '') AS TIMESTAMP) AS medication_start_time,
        TRY_CAST(NULLIF(STOP, '') AS TIMESTAMP) AS medication_stop_time,
        CAST(TRY_CAST(NULLIF(START, '') AS TIMESTAMP) AS DATE) AS medication_start_date,
        CAST(TRY_CAST(NULLIF(STOP, '') AS TIMESTAMP) AS DATE) AS medication_stop_date,
        CASE 
            WHEN NULLIF(STOP, '') IS NULL THEN TRUE 
            ELSE FALSE 
        END AS is_ongoing_prescription,
        NULLIF(CODE, '') AS medication_code,
        TRIM(DESCRIPTION) AS medication_description,
        TRY_CAST(NULLIF(BASE_COST, '') AS DECIMAL(12, 2)) AS base_cost,
        TRY_CAST(NULLIF(PAYER_COVERAGE, '') AS DECIMAL(12, 2)) AS payer_coverage,
        TRY_CAST(NULLIF(DISPENSES, '') AS INTEGER) AS dispenses,
        TRY_CAST(NULLIF(TOTALCOST, '') AS DECIMAL(12, 2)) AS total_cost,
        NULLIF(REASONCODE, '') AS reason_code,
        NULLIF(REASONDESCRIPTION, '') AS reason_description
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
            'medication_code',
            'medication_start_time'
        ]) }} AS medication_id,
        patient_id,
        encounter_id,
        payer_id,
        medication_start_time,
        medication_stop_time,
        medication_start_date,
        medication_stop_date,
        is_ongoing_prescription,
        medication_code,
        medication_description,
        base_cost,
        payer_coverage,
        dispenses,
        total_cost,
        reason_code,
        reason_description
    FROM renamed_and_cast
)

SELECT *
FROM with_surrogate_key
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY medication_id 
    ORDER BY medication_stop_time
) = 1
