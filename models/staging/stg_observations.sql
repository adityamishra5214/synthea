WITH source AS (
    SELECT * FROM {{ source('raw', 'observations') }}
),

renamed_and_cast AS (
    SELECT
        CAST(PATIENT AS VARCHAR) AS patient_id,
        CAST(ENCOUNTER AS VARCHAR) AS encounter_id,
        TRY_CAST(NULLIF("DATE", '') AS TIMESTAMP) AS observation_time,
        CAST(TRY_CAST(NULLIF("DATE", '') AS TIMESTAMP) AS DATE) AS observation_date,
        NULLIF(CODE, '') AS observation_code,
        TRIM(DESCRIPTION) AS observation_description,
        NULLIF(VALUE, '') AS observation_value,
        NULLIF(UNITS, '') AS observation_units,
        LOWER(TRIM("TYPE")) AS observation_type
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
            'observation_code',
            'observation_time',
            'observation_value'
        ]) }} AS observation_id,
        patient_id,
        encounter_id,
        observation_time,
        observation_date,
        observation_code,
        observation_description,
        observation_value,
        observation_units,
        observation_type
    FROM renamed_and_cast
)

SELECT *
FROM with_surrogate_key
QUALIFY ROW_NUMBER() OVER (PARTITION BY observation_id ORDER BY observation_time) = 1
