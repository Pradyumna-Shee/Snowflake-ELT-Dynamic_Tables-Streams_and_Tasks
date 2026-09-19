-- ============================================================
-- 02_bronze_data_load.sql
-- ============================================================
-- Purpose : Loads the SEC quarterly files (sub.txt, num.txt, tag.txt, pre.txt) from the stage
--           SEC_QUARTERLY_FILES_LANDING_STAGE into the four SOURCE_SEC_* tables in
--           BRONZE_SEC_FILINGS_STAGING.
-- Audit   : SOURCE_QUARTER is taken from the stage folder name (for example 2025q3);
--           SOURCE_FILE_NAME holds the full file path.
-- Before  : Deploy 01_platform_setup.sql and upload the quarterly files to the stage.
-- Re-runs : Safe. Files that are already loaded are skipped.
-- ============================================================


-- ============================================================
-- 1. Filing submissions (sub.txt) -> SOURCE_SEC_FILING_SUBMISSIONS
-- ============================================================
COPY INTO SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FILING_SUBMISSIONS
(
    -- Filing identity
    ADSH, CIK, NAME, SIC,
    -- Business address
    COUNTRYBA, STPRBA, CITYBA, ZIPBA, BAS1, BAS2, BAPH,
    -- Mailing address
    COUNTRYMA, STPRMA, CITYMA, ZIPMA, MAS1, MAS2,
    -- Incorporation and company history
    COUNTRYINC, STPRINC, EIN, FORMER, CHANGED,
    -- Filer status and fiscal year end
    AFS, WKSI, FYE,
    -- Filing details
    FORM, PERIOD, FY, FP, FILED, ACCEPTED, PREVRPT, DETAIL, INSTANCE, NCIKS, ACIKS,
    -- Audit columns
    SOURCE_QUARTER, SOURCE_FILE_NAME
)
FROM (
    SELECT
        -- Filing identity
        $1, $2, $3, $4,
        -- Business address
        $5, $6, $7, $8, $9, $10, $11,
        -- Mailing address
        $12, $13, $14, $15, $16, $17,
        -- Incorporation and company history
        $18, $19, $20, $21, $22,
        -- Filer status and fiscal year end
        $23, $24, $25,
        -- Filing details
        $26, $27, $28, $29, $30, $31, $32, $33, $34, $35, $36,
        -- Audit columns
        REGEXP_SUBSTR(METADATA$FILENAME, '[0-9]{4}q[1-4]'),
        METADATA$FILENAME
    FROM @SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE
)
PATTERN = '.*sub[.]txt.*';


-- ============================================================
-- 2. Reported financial values (num.txt) -> SOURCE_SEC_FINANCIAL_VALUES
-- ============================================================
COPY INTO SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
(
    -- Filing and tag
    ADSH, TAG, VERSION,
    -- Reporting period
    DDATE, QTRS,
    -- Value
    UOM, SEGMENTS, COREG, VALUE, FOOTNOTE,
    -- Audit columns
    SOURCE_QUARTER, SOURCE_FILE_NAME
)
FROM (
    SELECT
        -- Filing and tag
        $1, $2, $3,
        -- Reporting period
        $4, $5,
        -- Value
        $6, $7, $8, $9, $10,
        -- Audit columns
        REGEXP_SUBSTR(METADATA$FILENAME, '[0-9]{4}q[1-4]'),
        METADATA$FILENAME
    FROM @SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE
)
PATTERN = '.*num[.]txt.*';


-- ============================================================
-- 3. Financial tag definitions (tag.txt) -> SOURCE_SEC_TAG_DEFINITIONS
-- ============================================================
COPY INTO SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_TAG_DEFINITIONS
(
    -- Tag identity
    TAG, VERSION,
    -- Classification
    CUSTOM, ABSTRACT, DATATYPE, IORD, CRDR,
    -- Descriptions
    TLABEL, DOC,
    -- Audit columns
    SOURCE_QUARTER, SOURCE_FILE_NAME
)
FROM (
    SELECT
        -- Tag identity
        $1, $2,
        -- Classification
        $3, $4, $5, $6, $7,
        -- Descriptions
        $8, $9,
        -- Audit columns
        REGEXP_SUBSTR(METADATA$FILENAME, '[0-9]{4}q[1-4]'),
        METADATA$FILENAME
    FROM @SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE
)
PATTERN = '.*tag[.]txt.*';


-- ============================================================
-- 4. Financial statement presentation (pre.txt) -> SOURCE_SEC_STATEMENT_PRESENTATION
-- ============================================================
COPY INTO SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_STATEMENT_PRESENTATION
(
    -- Report location
    ADSH, REPORT, LINE,
    -- Statement type and format
    STMT, INPTH, RFILE,
    -- Tag and label
    TAG, VERSION, PLABEL, NEGATING,
    -- Audit columns
    SOURCE_QUARTER, SOURCE_FILE_NAME
)
FROM (
    SELECT
        -- Report location
        $1, $2, $3,
        -- Statement type and format
        $4, $5, $6,
        -- Tag and label
        $7, $8, $9, $10,
        -- Audit columns
        REGEXP_SUBSTR(METADATA$FILENAME, '[0-9]{4}q[1-4]'),
        METADATA$FILENAME
    FROM @SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE
)
PATTERN = '.*pre[.]txt.*';

-- ============================================================
-- 5. Load check: row count per source table and quarter
-- ============================================================
SELECT 'SOURCE_SEC_FILING_SUBMISSIONS' AS source_table, SOURCE_QUARTER, COUNT(*) AS row_count
FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FILING_SUBMISSIONS
GROUP BY SOURCE_QUARTER
UNION ALL
SELECT 'SOURCE_SEC_FINANCIAL_VALUES', SOURCE_QUARTER, COUNT(*)
FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
GROUP BY SOURCE_QUARTER
UNION ALL
SELECT 'SOURCE_SEC_TAG_DEFINITIONS', SOURCE_QUARTER, COUNT(*)
FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_TAG_DEFINITIONS
GROUP BY SOURCE_QUARTER
UNION ALL
SELECT 'SOURCE_SEC_STATEMENT_PRESENTATION', SOURCE_QUARTER, COUNT(*)
FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_STATEMENT_PRESENTATION
GROUP BY SOURCE_QUARTER
ORDER BY source_table, SOURCE_QUARTER;