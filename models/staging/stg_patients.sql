WITH source AS (
    SELECT * FROM {{ source('raw', 'patients') }}
),

renamed_and_cast AS (
    SELECT
        CAST(Id AS VARCHAR) AS patient_id,
        TRY_CAST(NULLIF(BIRTHDATE, '') AS DATE) AS birth_date,
        TRY_CAST(NULLIF(DEATHDATE, '') AS DATE) AS death_date,
        CASE 
            WHEN NULLIF(DEATHDATE, '') IS NOT NULL THEN TRUE 
            ELSE FALSE 
        END AS is_deceased,
        NULLIF(SSN, '') AS ssn,
        NULLIF(DRIVERS, '') AS drivers_license,
        NULLIF(PASSPORT, '') AS passport,
        NULLIF(PREFIX, '') AS prefix,
        NULLIF(FIRST, '') AS first_name,
        NULLIF(LAST, '') AS last_name,
        NULLIF(SUFFIX, '') AS suffix,
        NULLIF(MAIDEN, '') AS maiden_name,
        NULLIF(MARITAL, '') AS marital_status,
        LOWER(TRIM(RACE)) AS race,
        LOWER(TRIM(ETHNICITY)) AS ethnicity,
        UPPER(TRIM(GENDER)) AS gender,
        NULLIF(BIRTHPLACE, '') AS birthplace,
        NULLIF(ADDRESS, '') AS address,
        NULLIF(CITY, '') AS city,
        NULLIF(STATE, '') AS state,
        NULLIF(COUNTY, '') AS county,
        NULLIF(ZIP, '') AS zip_code,
        TRY_CAST(NULLIF(LAT, '') AS DOUBLE) AS latitude,
        TRY_CAST(NULLIF(LON, '') AS DOUBLE) AS longitude,
        TRY_CAST(NULLIF(HEALTHCARE_EXPENSES, '') AS DECIMAL(14, 2)) AS healthcare_expenses,
        TRY_CAST(NULLIF(HEALTHCARE_COVERAGE, '') AS DECIMAL(14, 2)) AS healthcare_coverage
    FROM source
    WHERE Id IS NOT NULL
)

SELECT *
FROM renamed_and_cast
QUALIFY ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY birth_date) = 1
