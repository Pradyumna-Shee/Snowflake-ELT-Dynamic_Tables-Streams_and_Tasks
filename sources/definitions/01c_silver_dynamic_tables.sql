-- 01c_silver_dynamic_tables.sql
-- Silver layer: one integrated table of typed financial facts.

-- Filter rules (parent company only, standard tags only, USD only, no segments) follow the approach of this open-source project:
--   https://github.com/HansjoergW/sec-fincancial-statement-data-set

-- PREVRPT means "Previous Report". It indicates whether the submission was subsequently amended:
--   1 = TRUE  -> the submission was later amended
--   0 = FALSE -> the submission was not subsequently amended
-- PREVRPT = '0' keeps filings that were not subsequently amended.
--   https://guides.newman.baruch.cuny.edu/c.php?g=188202&p=6006114

-- Financial facts (num.txt) joined to their filing (sub.txt) and tag meaning (tag.txt).
-- Columns converted from text to real types. Rows with bad values are filtered out.
-- BUSINESS_STATE_CODE and FILER_SIZE_CODE are at the end because DCM cannot reorder columns.

DEFINE DYNAMIC TABLE SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS
  TARGET_LAG = '1 day'
  WAREHOUSE = SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE
AS
SELECT
    -- Source
    v.SOURCE_QUARTER,
    -- Company and filing
    s.ADSH                                      AS FILING_ACCESSION_NUMBER,
    TRY_TO_NUMBER(s.CIK)                        AS COMPANY_CIK,
    s.NAME                                      AS COMPANY_NAME,
    TRY_TO_NUMBER(s.SIC)                        AS INDUSTRY_SIC_CODE,
    s.FORM                                      AS FORM_TYPE,
    TRY_TO_NUMBER(s.FY)                         AS FISCAL_YEAR,
    s.FP                                        AS FISCAL_PERIOD,
    TRY_TO_DATE(s.PERIOD, 'YYYYMMDD')           AS BALANCE_SHEET_DATE,
    TRY_TO_DATE(s.FILED, 'YYYYMMDD')            AS FILING_DATE,
    -- Financial tag
    v.TAG                                       AS TAG_NAME,
    t.TLABEL                                    AS TAG_LABEL,
    t.IORD                                      AS POINT_IN_TIME_OR_DURATION,
    -- Reported value
    TRY_TO_DATE(v.DDATE, 'YYYYMMDD')            AS VALUE_END_DATE,
    TRY_TO_NUMBER(v.QTRS)                       AS QUARTERS_COVERED,
    v.UOM                                       AS UNIT_OF_MEASURE,
    TRY_TO_NUMBER(v.VALUE, 28, 4)               AS REPORTED_VALUE,
    -- Company profile
    NULLIF(s.STPRBA, '')                        AS BUSINESS_STATE_CODE,
    NULLIF(s.AFS, '')                           AS FILER_SIZE_CODE
FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES v
JOIN SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FILING_SUBMISSIONS s
    ON  v.ADSH = s.ADSH
    AND v.SOURCE_QUARTER = s.SOURCE_QUARTER
JOIN SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_TAG_DEFINITIONS t
    ON  v.TAG = t.TAG
    AND v.VERSION = t.VERSION
    AND v.SOURCE_QUARTER = t.SOURCE_QUARTER
WHERE NULLIF(v.COREG, '') IS NULL        -- parent company only
  AND NULLIF(v.SEGMENTS, '') IS NULL     -- totals only, no segment breakdowns
  AND v.UOM = 'USD'                      -- US dollars only
  AND t.CUSTOM = '0'                     -- standard tags only
  AND TRY_TO_NUMBER(v.VALUE, 28, 4) IS NOT NULL
  AND s.PREVRPT = '0';                   -- filing was not later amended