-- 01d_gold_dimensions.sql
-- Gold layer: dimension tables shared by the fact tables.
-- All five are built from the silver table. State and filer size are not on the company dimension
-- because they can change from one filing to the next; they are kept on the fact tables.

-- Company: one row per company, using the name and SIC code from its latest filing.
DEFINE DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_COMPANY
  TARGET_LAG = '1 day'
  WAREHOUSE = SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE
AS
SELECT
    COMPANY_CIK,
    COMPANY_NAME,
    INDUSTRY_SIC_CODE
FROM SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS
WHERE COMPANY_CIK IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY COMPANY_CIK
    ORDER BY FILING_DATE DESC, FILING_ACCESSION_NUMBER DESC
) = 1;

-- Industry: one row per SIC code, with its industry division.
-- Row access rules use INDUSTRY_DIVISION.
DEFINE DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_INDUSTRY
  TARGET_LAG = '1 day'
  WAREHOUSE = SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE
AS
SELECT DISTINCT
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
    END AS INDUSTRY_DIVISION
FROM SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS
WHERE INDUSTRY_SIC_CODE IS NOT NULL;

-- Filer size: one row per filer status code seen in the data (from the AFS field of sub.txt).
-- A missing code is kept as NOT_STATED so every fact row has a match.
DEFINE DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_FILER_SIZE
  TARGET_LAG = '1 day'
  WAREHOUSE = SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE
AS
SELECT DISTINCT
    COALESCE(FILER_SIZE_CODE, 'NOT_STATED') AS FILER_SIZE_CODE,
    CASE FILER_SIZE_CODE
        WHEN '1-LAF' THEN 'Large Accelerated Filer'
        WHEN '2-ACC' THEN 'Accelerated Filer'
        WHEN '3-SRA' THEN 'Smaller Reporting Accelerated Filer'
        WHEN '4-NON' THEN 'Non-accelerated Filer'
        WHEN '5-SML' THEN 'Smaller Reporting Company'
        ELSE 'Not stated'
    END AS FILER_SIZE_NAME
FROM SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS;

-- State: one row per business address state code seen in the data.
-- US states and territories get a name. Any other code (for example Canadian provinces) is grouped as outside the United States.
DEFINE DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_STATE
  TARGET_LAG = '1 day'
  WAREHOUSE = SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE
AS
SELECT DISTINCT
    COALESCE(BUSINESS_STATE_CODE, 'NOT_STATED') AS BUSINESS_STATE_CODE,
    CASE BUSINESS_STATE_CODE
        WHEN 'AL' THEN 'Alabama'        WHEN 'AK' THEN 'Alaska'         WHEN 'AZ' THEN 'Arizona'
        WHEN 'AR' THEN 'Arkansas'       WHEN 'CA' THEN 'California'     WHEN 'CO' THEN 'Colorado'
        WHEN 'CT' THEN 'Connecticut'    WHEN 'DE' THEN 'Delaware'       WHEN 'DC' THEN 'District of Columbia'
        WHEN 'FL' THEN 'Florida'        WHEN 'GA' THEN 'Georgia'        WHEN 'HI' THEN 'Hawaii'
        WHEN 'ID' THEN 'Idaho'          WHEN 'IL' THEN 'Illinois'       WHEN 'IN' THEN 'Indiana'
        WHEN 'IA' THEN 'Iowa'           WHEN 'KS' THEN 'Kansas'         WHEN 'KY' THEN 'Kentucky'
        WHEN 'LA' THEN 'Louisiana'      WHEN 'ME' THEN 'Maine'          WHEN 'MD' THEN 'Maryland'
        WHEN 'MA' THEN 'Massachusetts'  WHEN 'MI' THEN 'Michigan'       WHEN 'MN' THEN 'Minnesota'
        WHEN 'MS' THEN 'Mississippi'    WHEN 'MO' THEN 'Missouri'       WHEN 'MT' THEN 'Montana'
        WHEN 'NE' THEN 'Nebraska'       WHEN 'NV' THEN 'Nevada'         WHEN 'NH' THEN 'New Hampshire'
        WHEN 'NJ' THEN 'New Jersey'     WHEN 'NM' THEN 'New Mexico'     WHEN 'NY' THEN 'New York'
        WHEN 'NC' THEN 'North Carolina' WHEN 'ND' THEN 'North Dakota'   WHEN 'OH' THEN 'Ohio'
        WHEN 'OK' THEN 'Oklahoma'       WHEN 'OR' THEN 'Oregon'         WHEN 'PA' THEN 'Pennsylvania'
        WHEN 'RI' THEN 'Rhode Island'   WHEN 'SC' THEN 'South Carolina' WHEN 'SD' THEN 'South Dakota'
        WHEN 'TN' THEN 'Tennessee'      WHEN 'TX' THEN 'Texas'          WHEN 'UT' THEN 'Utah'
        WHEN 'VT' THEN 'Vermont'        WHEN 'VA' THEN 'Virginia'       WHEN 'WA' THEN 'Washington'
        WHEN 'WV' THEN 'West Virginia'  WHEN 'WI' THEN 'Wisconsin'      WHEN 'WY' THEN 'Wyoming'
        WHEN 'PR' THEN 'Puerto Rico'    WHEN 'GU' THEN 'Guam'           WHEN 'VI' THEN 'US Virgin Islands'
        WHEN 'AS' THEN 'American Samoa' WHEN 'MP' THEN 'Northern Mariana Islands'
        ELSE CASE WHEN BUSINESS_STATE_CODE IS NULL THEN 'Not stated' ELSE 'Outside the United States' END
    END AS BUSINESS_STATE_NAME
FROM SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS;

-- Date: one row per period end date seen in the data, with calendar year and quarter.
DEFINE DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_DATE
  TARGET_LAG = '1 day'
  WAREHOUSE = SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE
AS
SELECT DISTINCT
    BALANCE_SHEET_DATE                                  AS PERIOD_END_DATE,
    YEAR(BALANCE_SHEET_DATE)                            AS CALENDAR_YEAR,
    QUARTER(BALANCE_SHEET_DATE)                         AS CALENDAR_QUARTER,
    YEAR(BALANCE_SHEET_DATE) || '-Q' || QUARTER(BALANCE_SHEET_DATE) AS CALENDAR_YEAR_QUARTER
FROM SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS
WHERE BALANCE_SHEET_DATE IS NOT NULL;