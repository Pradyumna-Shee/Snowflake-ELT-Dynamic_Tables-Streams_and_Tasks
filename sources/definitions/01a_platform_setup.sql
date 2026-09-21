-- 01a_platform_setup.sql
-- SEC Financial Data Pipeline
-- Sets up the Snowflake objects shared by all layers: compute, database, schemas and the file landing area.

-- ============================================================
-- References
-- ============================================================
-- Data source (SEC Financial Statement Data Sets, quarterly files sub, num, tag, pre):
--   https://www.sec.gov/data-research/sec-markets-data/financial-statement-data-sets
--      sub.txt  = filing/submission information
--      num.txt  = reported numeric values
--      tag.txt  = XBRL tag definitions
--      pre.txt  = statement presentation information

-- SEC Financial Statement Data Sets and field definitions (PDF):
--   https://www.sec.gov/data/financial-statements/aqfs.pdf
--      Used to understand the main fields and the relationships between the files.
--          sub.txt and num.txt are joined using ADSH; num.txt and tag.txt are joined using TAG + VERSION
--      Also used for fields such as COREG, QTRS, DDATE, CUSTOM, PREVRPT, IORD, PERIOD, FILED and SIC.

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
-- Loading objects (used by the bronze load in scripts/02_bronze_data_load.sql)
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