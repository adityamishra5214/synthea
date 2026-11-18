WITH source AS (
    SELECT * FROM {{ source('raw', 'procedures') }}
),

renamed_and_cast AS (
    SELECT
        CAST(PATIENT AS VARCHAR) AS patient_id,
        CAST(ENCOUNTER AS VARCHAR) AS encounter_id,
        TRY_CAST(NULLIF("DATE", '') AS TIMESTAMP) AS procedure_time,
        CAST(TRY_CAST(NULLIF("DATE", '') AS TIMESTAMP) AS DATE) AS procedure_date,
        NULLIF(CODE, '') AS procedure_code,
        TRIM(DESCRIPTION) AS procedure_description,
        TRY_CAST(NULLIF(BASE_COST, '') AS DECIMAL(12, 2)) AS base_cost,
        NULLIF(REASONCODE, '') AS reason_code,
        NULLIF(REASONDESCRIPTION, '') AS reason_description
    FROM source
    WHERE PATIENT IS NOT NULL
      AND "DATE" IS NOT NULL
      AND CODE IS NOT NULL
),

with_surrogate_key AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key([
            'patient_id',
            'encounter_id',
            'procedure_code',
            'procedure_time'
        ]) }} AS procedure_id,
        patient_id,
        encounter_id,
        procedure_time,
        procedure_date,
        procedure_code,
        procedure_description,
        base_cost,
        reason_code,
        reason_description
    FROM renamed_and_cast
)

SELECT *
FROM with_surrogate_key
QUALIFY ROW_NUMBER() OVER (PARTITION BY procedure_id ORDER BY procedure_time) = 1
