-- 01_platform_setup.sql
-- SEC Financial Data Pipeline
-- Set up the Snowflake objects used to load, transform and analyse the SEC Financial Statement Data Sets.

-- ============================================================
-- References
-- ============================================================
-- Data source (SEC Financial Statement Data Sets, quarterly files sub, num, tag, pre):
--   https://www.sec.gov/data-research/sec-markets-data/financial-statement-data-sets
--      sub.txt  = filing/submission information
--      num.txt  = reported numeric values
--      tag.txt  = XBRL tag definitions
--      pre.txt  = statement presentation information

-- SEC Financial Statement Data Sets and field definitions: (PDF):
--   https://www.sec.gov/data/financial-statements/aqfs.pdf
--      This document was used to understand the main fields and the relationships between the files. 
--          sub.txt and num.txt are joined using ADSH; num.txt and tag.txt are joined using TAG + VERSION
--      It was also used to understand fields such as COREG, QTRS, DDATE, CUSTOM, PREVRPT, IORD, PERIOD, FILED and SIC.

-- Silver Layer Filter (parent company only, standard tags only, USD only, no segments)
-- The rules for keeping parent-company, standard-tag, USD and non-segment data follow the approach used in this open-source project:
--   https://github.com/HansjoergW/sec-fincancial-statement-data-set

-- PREVRPT means "Previous Report". It indicates whether the submission information was subsequently amended:
--   1 = TRUE  -> the submission was later amended
--   0 = FALSE -> the submission was not subsequently amended
-- PREVRPT = '0' keeps filings that were not subsequently amended.
--   https://guides.newman.baruch.cuny.edu/c.php?g=188202&p=6006114

-- Snowflake Implementation Reference:
-- This project was useful as a reference for separating the raw SEC data from the typed/transformed tables. 
-- In this project, the Bronze layer keeps the source values as text and type conversion is handled later.
--   https://github.com/BigDataIA-Spring2025-4/SEC-Bridge
--
-- SEC statement: SEC data may contain inaccuracies and is used here for analysis.

-- ============================================================
-- Compute
-- Small warehouse (X-SMALL) used for loading the SEC files and running the Silver and Gold transformations. 
-- ============================================================

-- Warehouse: compute used for loading, transforming, and analysing SEC data.
DEFINE WAREHOUSE SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE
  WITH
    WAREHOUSE_SIZE = 'X-SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

-- ============================================================
-- Database and schemas (medallion layers: Bronze, Silver and Gold schemas) for the project.
-- ============================================================

-- Database: main container for all SEC financial data layers.
DEFINE DATABASE SEC_FINANCIAL_DATA;

-- Bronze: stages SEC source files with minimal transformation.
DEFINE SCHEMA SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING;

-- Silver: merges the SEC tables into one integrated dataset, the base for the gold layer.
DEFINE SCHEMA SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS;

-- Gold: final layer for financial analytics and reporting, with business-ready datasets.
DEFINE SCHEMA SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING;


-- ============================================================
-- Bronze: loading objects
-- ============================================================

-- File format: SEC files are tab-delimited with a header row. Quotes are plain text, not wrappers.

DEFINE FILE FORMAT SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_TAB_DELIMITED_FILE_FORMAT
  TYPE = CSV
  FIELD_DELIMITER = '\t'
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = NONE
  ENCODING = 'UTF8';

-- Stage: landing area for the quarterly SEC files uploaded from the desktop.
DEFINE STAGE SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE
  FILE_FORMAT = SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_TAB_DELIMITED_FILE_FORMAT;

-- ============================================================
-- Bronze: source tables (all columns as text, exactly as received; casting happens in silver)
-- ============================================================

-- Filing submissions (from sub.txt): one row per EDGAR filing (filer, form type, period, filing dates).

DEFINE TABLE SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FILING_SUBMISSIONS (
  ADSH STRING, CIK STRING, NAME STRING, SIC STRING,
  COUNTRYBA STRING, STPRBA STRING, CITYBA STRING, ZIPBA STRING, BAS1 STRING, BAS2 STRING, BAPH STRING,
  COUNTRYMA STRING, STPRMA STRING, CITYMA STRING, ZIPMA STRING, MAS1 STRING, MAS2 STRING,
  COUNTRYINC STRING, STPRINC STRING, EIN STRING, FORMER STRING, CHANGED STRING,
  AFS STRING, WKSI STRING, FYE STRING, FORM STRING, PERIOD STRING, FY STRING, FP STRING,
  FILED STRING, ACCEPTED STRING, PREVRPT STRING, DETAIL STRING, INSTANCE STRING, NCIKS STRING, ACIKS STRING,
  SOURCE_QUARTER STRING,
  SOURCE_FILE_NAME STRING,
  LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Financial values (from num.txt): one row per reported numeric value.

DEFINE TABLE SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES (
  ADSH STRING, TAG STRING, VERSION STRING, DDATE STRING, QTRS STRING, UOM STRING,
  SEGMENTS STRING, COREG STRING, VALUE STRING, FOOTNOTE STRING,
  SOURCE_QUARTER STRING,
  SOURCE_FILE_NAME STRING,
  LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Tag definitions (from tag.txt): meaning of each standard and custom XBRL tag.

DEFINE TABLE SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_TAG_DEFINITIONS (
  TAG STRING, VERSION STRING, CUSTOM STRING, ABSTRACT STRING, DATATYPE STRING,
  IORD STRING, CRDR STRING, TLABEL STRING, DOC STRING,
  SOURCE_QUARTER STRING,
  SOURCE_FILE_NAME STRING,
  LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Statement presentation (from pre.txt): where and how each tag appears on the financial statements.

DEFINE TABLE SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_STATEMENT_PRESENTATION (
  ADSH STRING, REPORT STRING, LINE STRING, STMT STRING, INPTH STRING, RFILE STRING,
  TAG STRING, VERSION STRING, PLABEL STRING, NEGATING STRING,
  SOURCE_QUARTER STRING,
  SOURCE_FILE_NAME STRING,
  LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);



-- ============================================================
-- Silver Layer: Dynamic Tables
-- ============================================================

-- Financial facts (num.txt) joined to their filing (sub.txt) and tag meaning (tag.txt).
-- Columns converted from varchar to real types. Rows with bad values are filtered out.

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
        -- Company profile (added at the end, DCM cannot reorder columns)
    NULLIF(s.STPRBA, '') AS BUSINESS_STATE_CODE,
    NULLIF(s.AFS, '') AS FILER_SIZE_CODE
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


-- ============================================================
-- Gold Layer: Dynamic Table
-- ============================================================

-- Quarterly profitability per company: revenue, net income and net profit margin.
-- Built from 10-Q filings, using the value that covers the 3 months ending on the filing's period date.

DEFINE DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.SEC_COMPANY_QUARTERLY_PROFITABILITY
  TARGET_LAG = '1 day'
  WAREHOUSE = SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE
AS
SELECT
    SOURCE_QUARTER,
    COMPANY_CIK,
    COMPANY_NAME,
    INDUSTRY_SIC_CODE,
    CASE
        WHEN INDUSTRY_SIC_CODE BETWEEN 100  AND 999  THEN 'Agriculture, Forestry and Fishing'
        WHEN INDUSTRY_SIC_CODE BETWEEN 1000 AND 1499 THEN 'Mining'
        WHEN INDUSTRY_SIC_CODE BETWEEN 1500 AND 1799 THEN 'Construction'
        WHEN INDUSTRY_SIC_CODE BETWEEN 2000 AND 3999 THEN 'Manufacturing'
        WHEN INDUSTRY_SIC_CODE BETWEEN 4000 AND 4999 THEN 'Transportation, Communications and Utilities'
        WHEN INDUSTRY_SIC_CODE BETWEEN 5000 AND 5199 THEN 'Wholesale Trade'
        WHEN INDUSTRY_SIC_CODE BETWEEN 5200 AND 5999 THEN 'Retail Trade'
        WHEN INDUSTRY_SIC_CODE BETWEEN 6000 AND 6799 THEN 'Finance, Insurance and Real Estate'
        WHEN INDUSTRY_SIC_CODE BETWEEN 7000 AND 8999 THEN 'Services'
        WHEN INDUSTRY_SIC_CODE BETWEEN 9100 AND 9999 THEN 'Public Administration'
        ELSE 'Unclassified'
    END                                                 AS INDUSTRY_DIVISION,
    FISCAL_YEAR,
    FISCAL_PERIOD,
    BALANCE_SHEET_DATE                                  AS QUARTER_END_DATE,
    COALESCE(
        MAX(CASE WHEN TAG_NAME = 'RevenueFromContractWithCustomerExcludingAssessedTax' THEN REPORTED_VALUE END),
        MAX(CASE WHEN TAG_NAME = 'Revenues' THEN REPORTED_VALUE END)
    )                                                   AS REVENUE_USD,
    MAX(CASE WHEN TAG_NAME = 'NetIncomeLoss' THEN REPORTED_VALUE END) AS NET_INCOME_USD,
    ROUND(
        MAX(CASE WHEN TAG_NAME = 'NetIncomeLoss' THEN REPORTED_VALUE END)
        / NULLIF(COALESCE(
            MAX(CASE WHEN TAG_NAME = 'RevenueFromContractWithCustomerExcludingAssessedTax' THEN REPORTED_VALUE END),
            MAX(CASE WHEN TAG_NAME = 'Revenues' THEN REPORTED_VALUE END)
        ), 0) * 100, 2
    )                                                   AS NET_PROFIT_MARGIN_PERCENT
FROM SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS
WHERE FORM_TYPE = '10-Q'
  AND QUARTERS_COVERED = 1
  AND VALUE_END_DATE = BALANCE_SHEET_DATE
  AND TAG_NAME IN ('RevenueFromContractWithCustomerExcludingAssessedTax', 'Revenues', 'NetIncomeLoss')
GROUP BY SOURCE_QUARTER, FILING_ACCESSION_NUMBER, COMPANY_CIK, COMPANY_NAME, INDUSTRY_SIC_CODE,
         FISCAL_YEAR, FISCAL_PERIOD, BALANCE_SHEET_DATE
HAVING REVENUE_USD >= 1000000
   AND NET_INCOME_USD IS NOT NULL
   AND NET_INCOME_USD <= REVENUE_USD;