-- 03_streams_and_tasks.sql
-- SEC Financial Data Pipeline
-- Load new quarterly SEC files on a schedule and refresh the Silver and Gold layers only when new data arrives.

-- ============================================================
-- Load log
-- Bronze table that records how many rows each load added, per quarter.
-- ============================================================

-- Load log: one row per quarter per run of the refresh task, written from the stream below.
DEFINE TABLE SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_FINANCIAL_VALUES_LOAD_LOG (
  LOGGED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
  SOURCE_QUARTER STRING,
  ROWS_LOADED_COUNT NUMBER
);

-- ============================================================
-- Stream
-- Tracks the rows added to the financial values table since the last time it was read.
-- ============================================================

-- Stream: shows only new rows in SOURCE_SEC_FINANCIAL_VALUES. Append only, because bronze rows are never updated.
DEFINE STREAM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES_NEW_ROWS_STREAM
  ON TABLE SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
  APPEND_ONLY = TRUE;

-- ============================================================
-- Task 1: load new files
-- ============================================================

-- Runs every day at 06:00 UTC. Loads any new files from the landing stage into the four bronze tables.
-- Files that were already loaded are skipped.
DEFINE TASK SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LOAD_TASK
  WAREHOUSE = SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE
  SCHEDULE = 'USING CRON 0 6 * * * UTC'
AS
BEGIN

  -- Filing submissions (sub.txt)
  COPY INTO SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FILING_SUBMISSIONS
  FROM (
    SELECT
      $1, $2, $3, $4, $5, $6, $7, $8, $9,
      $10, $11, $12, $13, $14, $15, $16, $17, $18,
      $19, $20, $21, $22, $23, $24, $25, $26, $27,
      $28, $29, $30, $31, $32, $33, $34, $35, $36,
      REGEXP_SUBSTR(METADATA$FILENAME, '[0-9]{4}q[1-4]'),
      METADATA$FILENAME
    FROM @SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE
  )
  PATTERN = '.*sub[.]txt.*';

  -- Financial values (num.txt)
  COPY INTO SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
  FROM (
    SELECT
      $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
      REGEXP_SUBSTR(METADATA$FILENAME, '[0-9]{4}q[1-4]'),
      METADATA$FILENAME
    FROM @SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE
  )
  PATTERN = '.*num[.]txt.*';

  -- Tag definitions (tag.txt)
  COPY INTO SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_TAG_DEFINITIONS
  FROM (
    SELECT
      $1, $2, $3, $4, $5, $6, $7, $8, $9,
      REGEXP_SUBSTR(METADATA$FILENAME, '[0-9]{4}q[1-4]'),
      METADATA$FILENAME
    FROM @SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE
  )
  PATTERN = '.*tag[.]txt.*';

  -- Statement presentation (pre.txt)
  COPY INTO SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_STATEMENT_PRESENTATION
  FROM (
    SELECT
      $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
      REGEXP_SUBSTR(METADATA$FILENAME, '[0-9]{4}q[1-4]'),
      METADATA$FILENAME
    FROM @SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE
  )
  PATTERN = '.*pre[.]txt.*';

END;

-- ============================================================
-- Task 2: log the new rows and refresh Silver and Gold
-- ============================================================

-- Runs right after task 1, but only if the stream has new rows. Otherwise it does nothing.
-- Reading the stream in the INSERT marks those rows as processed.

DEFINE TASK SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_NEW_DATA_LOG_AND_REFRESH_TASK
  WAREHOUSE = SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE
  AFTER SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LOAD_TASK
  WHEN SYSTEM$STREAM_HAS_DATA('SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES_NEW_ROWS_STREAM')
AS
BEGIN

  -- Log: rows added per quarter
  INSERT INTO SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_FINANCIAL_VALUES_LOAD_LOG (SOURCE_QUARTER, ROWS_LOADED_COUNT)
  SELECT SOURCE_QUARTER, COUNT(*)
  FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES_NEW_ROWS_STREAM
  GROUP BY SOURCE_QUARTER;

  -- Refresh Silver first, because Gold reads from Silver
  ALTER DYNAMIC TABLE SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS REFRESH;
  ALTER DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.SEC_COMPANY_QUARTERLY_PROFITABILITY REFRESH;

END;