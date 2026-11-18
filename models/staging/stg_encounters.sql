WITH source AS (
    SELECT * FROM {{ source('raw', 'encounters') }}
),

renamed_and_cast AS (
    SELECT
        CAST(Id AS VARCHAR) AS encounter_id,
        TRY_CAST(NULLIF(START, '') AS TIMESTAMP) AS encounter_start_time,
        TRY_CAST(NULLIF(STOP, '') AS TIMESTAMP) AS encounter_stop_time,
        CAST(PATIENT AS VARCHAR) AS patient_id,
        NULLIF(ORGANIZATION, '') AS organization_id,
        NULLIF(PROVIDER, '') AS provider_id,
        NULLIF(PAYER, '') AS payer_id,
        LOWER(TRIM(ENCOUNTERCLASS)) AS encounter_class,
        NULLIF(CODE, '') AS encounter_code,
        NULLIF(DESCRIPTION, '') AS encounter_description,
        TRY_CAST(NULLIF(BASE_ENCOUNTER_COST, '') AS DECIMAL(12, 2)) AS base_encounter_cost,
        TRY_CAST(NULLIF(TOTAL_CLAIM_COST, '') AS DECIMAL(12, 2)) AS total_claim_cost,
        TRY_CAST(NULLIF(PAYER_COVERAGE, '') AS DECIMAL(12, 2)) AS payer_coverage,
        NULLIF(REASONCODE, '') AS reason_code,
        NULLIF(REASONDESCRIPTION, '') AS reason_description
    FROM source
    WHERE Id IS NOT NULL
)

SELECT *
FROM renamed_and_cast
QUALIFY ROW_NUMBER() OVER (PARTITION BY encounter_id ORDER BY encounter_start_time) = 1
