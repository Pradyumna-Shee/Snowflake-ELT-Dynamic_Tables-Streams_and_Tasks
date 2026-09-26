-- 05_development_scratchpad.sql
-- SEC Financial Data Pipeline
-- Working queries used while building the pipeline: checks on each layer, refreshes and sanity checks.
-- Run one statement at a time (select it, then Ctrl+Enter).

-- ============================================================
-- Bronze checks
-- ============================================================

-- Reload from scratch: empties a bronze table and clears its load history, so the COPY INTO in
-- 02_bronze_data_load.sql loads all files again. Commented out on purpose, remove the dashes only when needed.
-- TRUNCATE TABLE SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FILING_SUBMISSIONS;

-- Sample rows: confirm the tab-delimited columns landed in the right fields after loading.
SELECT TOP 10 *
FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES;

-- Row count per bronze table: confirm all four files (sub, num, tag, pre) were loaded.
SELECT 'SOURCE_SEC_FILING_SUBMISSIONS' AS table_name, COUNT(*) AS row_count FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FILING_SUBMISSIONS
UNION ALL
SELECT 'SOURCE_SEC_FINANCIAL_VALUES', COUNT(*) FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
UNION ALL
SELECT 'SOURCE_SEC_TAG_DEFINITIONS', COUNT(*) FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_TAG_DEFINITIONS
UNION ALL
SELECT 'SOURCE_SEC_STATEMENT_PRESENTATION', COUNT(*) FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_STATEMENT_PRESENTATION;

-- ============================================================
-- Silver checks
-- ============================================================

-- Bronze vs silver: how many financial values survive the silver filters.
-- Bronze counts every value; silver keeps parent company, standard tags, USD, no segments, not amended.
SELECT
    (SELECT COUNT(*) FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES) AS bronze_rows,
    (SELECT COUNT(*) FROM SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS) AS silver_rows;

-- Tag coverage: how many companies report each tag we plan to use in gold.
-- Used to decide which revenue tag to use, since many companies use Revenues instead of the contract-revenue tag.
SELECT TAG_NAME, COUNT(DISTINCT COMPANY_CIK) AS companies
FROM SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS
WHERE TAG_NAME IN ('Revenues', 'RevenueFromContractWithCustomerExcludingAssessedTax', 'NetIncomeLoss', 'Assets')
GROUP BY TAG_NAME
ORDER BY companies DESC;

-- ============================================================
-- Gold checks
-- ============================================================

-- Gold row count: number of company-quarters that pass all gold filters.
SELECT COUNT(*) AS company_quarters
FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.SEC_COMPANY_QUARTERLY_PROFITABILITY;

-- Largest companies by revenue: sanity check that the revenue and net income values look right for known companies.
SELECT COMPANY_NAME, QUARTER_END_DATE, REVENUE_USD, NET_INCOME_USD, NET_PROFIT_MARGIN_PERCENT
FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.SEC_COMPANY_QUARTERLY_PROFITABILITY
ORDER BY REVENUE_USD DESC
LIMIT 10;

-- Final result: top 3 companies by net profit margin in each industry division.
-- Also used to find bad margins (net income above revenue, tiny revenue) that led to the filters in gold.
SELECT
    INDUSTRY_DIVISION,
    COMPANY_NAME,
    QUARTER_END_DATE,
    REVENUE_USD,
    NET_INCOME_USD,
    NET_PROFIT_MARGIN_PERCENT
FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.SEC_COMPANY_QUARTERLY_PROFITABILITY
QUALIFY ROW_NUMBER() OVER (
            PARTITION BY INDUSTRY_DIVISION
            ORDER BY NET_PROFIT_MARGIN_PERCENT DESC
        ) <= 3
ORDER BY INDUSTRY_DIVISION, NET_PROFIT_MARGIN_PERCENT DESC;

-- ============================================================
-- Dynamic Tables: status and manual refresh
-- ============================================================

-- Status: row counts, target lag, refresh mode and last refresh time of the Silver and Gold Dynamic Tables.
SHOW DYNAMIC TABLES IN DATABASE SEC_FINANCIAL_DATA;

-- Migration to the fact constellation: gold used to be one wide table (SEC_COMPANY_QUARTERLY_PROFITABILITY).
-- Dropped it and silver, then let DCM recreate them from the new definitions (5 dimensions + 3 fact tables),
-- and manually refreshed instead of waiting for the 1 day lag.
-- Refresh Silver first, because Gold reads from Silver.
DROP DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.SEC_COMPANY_QUARTERLY_PROFITABILITY;
DROP DYNAMIC TABLE SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS;

ALTER DYNAMIC TABLE SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS REFRESH;

-- Old name kept here as the last statement run against it before the fact tables replaced it for good.
ALTER DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.SEC_COMPANY_QUARTERLY_PROFITABILITY REFRESH;

-- Filer size spread: how rows split across large/small filers and how many distinct states each covers.
-- Sanity check for the filer-size dimension before building the filer-size report.
SELECT FILER_SIZE_CODE, COUNT(*) AS ROW_COUNT, COUNT(DISTINCT BUSINESS_STATE_CODE) AS DISTINCT_STATES
FROM SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS
GROUP BY FILER_SIZE_CODE
ORDER BY ROW_COUNT DESC;

-- Column check: confirm the silver table has the columns gold's dimension tables need to join on.
DESCRIBE TABLE SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS;

-- Dimension row counts: confirm all five gold dimensions built (company, industry, filer size, state, date).
SELECT 'DIM_COMPANY' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_COMPANY
UNION ALL SELECT 'DIM_INDUSTRY', COUNT(*) FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_INDUSTRY
UNION ALL SELECT 'DIM_FILER_SIZE', COUNT(*) FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_FILER_SIZE
UNION ALL SELECT 'DIM_STATE', COUNT(*) FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_STATE
UNION ALL SELECT 'DIM_DATE', COUNT(*) FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_DATE;

-- First manual refresh of the three new fact tables, once they existed alongside the dimensions.
ALTER DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_PROFITABILITY REFRESH;
ALTER DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_FINANCIAL_POSITION REFRESH;
ALTER DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_FILING REFRESH;

-- Orphan check: every fact row should join back to a company in DIM_COMPANY. ROWS_WITHOUT_COMPANY
-- should be 0 for all three; anything else means the join key or the dimension load is wrong.
SELECT 'FACT_QUARTERLY_PROFITABILITY' AS TABLE_NAME, COUNT(*) AS ROW_COUNT,
       SUM(IFF(c.COMPANY_CIK IS NULL, 1, 0)) AS ROWS_WITHOUT_COMPANY
FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_PROFITABILITY f
LEFT JOIN SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_COMPANY c ON f.COMPANY_CIK = c.COMPANY_CIK
UNION ALL
SELECT 'FACT_QUARTERLY_FINANCIAL_POSITION', COUNT(*), SUM(IFF(c.COMPANY_CIK IS NULL, 1, 0))
FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_FINANCIAL_POSITION f
LEFT JOIN SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_COMPANY c ON f.COMPANY_CIK = c.COMPANY_CIK
UNION ALL
SELECT 'FACT_FILING', COUNT(*), SUM(IFF(c.COMPANY_CIK IS NULL, 1, 0))
FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_FILING f
LEFT JOIN SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_COMPANY c ON f.COMPANY_CIK = c.COMPANY_CIK;

-- ============================================================
-- RBAC: testing row-level and column-level access per role
-- ============================================================

-- Analyst role: should see every industry and every column, including dollar figures.
USE ROLE SEC_ANALYST_ROLE;
SELECT * FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY;

-- Industry analyst role: should see only its assigned industries, but still the dollar columns.
USE ROLE SEC_INDUSTRY_ANALYST_ROLE;
SELECT * FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY;

-- Public reporter role, secondary roles dropped: proves the row-level view depends on the session's
-- roles, not just on ACCOUNTADMIN having access to everything.
USE SECONDARY ROLES NONE;
USE ROLE SEC_PUBLIC_REPORTER_ROLE;

SELECT CURRENT_ROLE(), IS_ROLE_IN_SESSION('SEC_ANALYST_ROLE');

-- This now should give an access Error: SEC_PUBLIC_REPORTER_ROLE has no grant on the dollar-column view.
SELECT * FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY;

-- Industry analyst again, this time with its own warehouse: confirms the row filter still works
-- outside of ACCOUNTADMIN's warehouse, and returns a smaller row count than the analyst role above.
USE SECONDARY ROLES NONE;
USE ROLE SEC_INDUSTRY_ANALYST_ROLE;
USE WAREHOUSE SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE;

SELECT * FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY;
SELECT COUNT(*) FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY;

-- Column-level check: the _PUBLIC view (no dollar columns) vs the full view, same role, same rows.
-- Confirms the horizontal (column) split is independent of the vertical (row) split.
SELECT * FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY_PUBLIC;
SELECT * FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY;

USE ROLE ACCOUNTADMIN;

-- Evaluating Report B: filer size profitability (row and column split).
USE SECONDARY ROLES NONE;
USE ROLE SEC_INDUSTRY_ANALYST_ROLE;
USE WAREHOUSE SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE;

SELECT * FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_FILER_SIZE_PROFITABILITY;

-- State coverage: how many distinct companies filed from each state, used to pick a sensible
-- state grouping and to sanity-check the state dimension before building Report C.
SELECT s.BUSINESS_STATE_NAME, COUNT(DISTINCT f.COMPANY_CIK) AS COMPANY_COUNT
FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_PROFITABILITY f
JOIN SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.DIM_STATE s ON f.BUSINESS_STATE_CODE = s.BUSINESS_STATE_CODE
GROUP BY s.BUSINESS_STATE_NAME
ORDER BY COMPANY_COUNT DESC;

-- Evaluating Report C: state profitability, as the analyst role would see it.
USE SECONDARY ROLES NONE;
USE ROLE SEC_ANALYST_ROLE;
USE WAREHOUSE SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE;

SELECT * FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_STATE_PROFITABILITY
ORDER BY TOTAL_NET_INCOME_USD DESC;

-- Evaluating Report D: the data-owner row funnel (row counts at each filter step, bronze through gold).
-- Dropped afterwards because it needs to be rebuilt to break the funnel out by SOURCE_QUARTER
-- before it makes sense with more than one quarter loaded.
USE SECONDARY ROLES NONE;
USE ROLE SEC_DATA_OWNER_ROLE;
USE WAREHOUSE SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE;

SELECT * FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_DATA_OWNER_ROW_FUNNEL;

DROP VIEW SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_DATA_OWNER_ROW_FUNNEL;

-- ============================================================
-- Key rotation (Colab / CLI access)
-- ============================================================

-- Replaced the RSA public key used for key-pair authentication (Colab, Snow CLI), unrelated to the
-- pipeline itself. Key value trimmed from history below is not the current key.
USE ROLE ACCOUNTADMIN;
ALTER USER PRADYUMNASHEE SET RSA_PUBLIC_KEY='MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsuVBLWaCvXlBhGDZG/8xxLyxG7cm/BUUW51eNcP76p2Zu+32JZWulkpSPc/zdbHm7eDVnccg57NME/D5TobDthS1VBZKhyqTPYeQ8KTE0vHfXYvoNx8BnkavaJnPZ63u21OH+HpbjLZOewhxLeRr9Qt3bWv/1M9eK/nBBXzaf7vPlHo4qKTMgz/2JTBccTOLQNwU5KAk6wnN1ZxSmjzddYt1PyvihE4dimcgth5NcXE9UWg806PzfLPv7QabWjGRjcPyIMwQWpkUa1zyXIkJ4nCpzTgM5wAqZ61G+GZDnvNSVfZMbkfWth5GhmeXesLqXB87DVtAjLS8FtD1GkIXbwIDAQAB';

-- ============================================================
-- Loading 2025q4, 2026q1, 2026q2: diagnosing and fixing the load task
-- ============================================================

-- State before loading: confirms only 2025q3 is in bronze at this point, for all four tables.
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

-- Confirms the new quarter files (sub/num/tag/pre for 2025q4, 2026q1, 2026q2) are already sitting
-- in the internal stage, uploaded via the Snow CLI, before trying to load them.
LIST @SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE;

-- Both tasks were suspended; resume them so the load task can actually be triggered.
ALTER TASK SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_NEW_DATA_LOG_AND_REFRESH_TASK RESUME;
ALTER TASK SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LOAD_TASK RESUME;

-- First manual trigger of the load task, expecting it to pick up the three new quarters.
EXECUTE TASK SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LOAD_TASK;

-- Result: task run shows FAILED. Row count query above, re-run at this point, still showed only
-- 2025q3 in every bronze table, so nothing was loaded.
SELECT NAME, STATE, ERROR_MESSAGE, SCHEDULED_TIME, COMPLETED_TIME
FROM TABLE(SEC_FINANCIAL_DATA.INFORMATION_SCHEMA.TASK_HISTORY())
WHERE NAME LIKE 'SEC_%'
ORDER BY SCHEDULED_TIME DESC
LIMIT 10;

-- Retried once more to confirm it wasn't a one-off, then read the ERROR_MESSAGE in full.
-- Result: same failure both times - "SQL compilation error: Insert value list does not match
-- column list expecting 39 but got 38" on the first COPY INTO (sub.txt). Root cause: the task's
-- COPY INTO statements have no explicit target column list, unlike the working manual script in
-- 02_bronze_data_load.sql, so Snowflake expects a value for every column including LOADED_AT
-- (which has a DEFAULT and should be left out).
EXECUTE TASK SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LOAD_TASK;

SELECT NAME, STATE, ERROR_MESSAGE, SCHEDULED_TIME, COMPLETED_TIME
FROM TABLE(SEC_FINANCIAL_DATA.INFORMATION_SCHEMA.TASK_HISTORY())
WHERE NAME LIKE 'SEC_%'
ORDER BY SCHEDULED_TIME DESC
LIMIT 10;

-- Fix applied to 03_streams_and_tasks.sql in the Workspace (added explicit column lists to all four
-- COPY INTO statements), but the live TASK object doesn't pick that up just from editing the file -
-- no deploy step found for it. Rather than chase that, ran the same four corrected COPY INTO
-- statements directly here, which is exactly what the task should have done.
-- Result: all three new quarters loaded cleanly into all four bronze tables (see file counts below).
COPY INTO SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FILING_SUBMISSIONS
(ADSH, CIK, NAME, SIC, COUNTRYBA, STPRBA, CITYBA, ZIPBA, BAS1, BAS2, BAPH,
 COUNTRYMA, STPRMA, CITYMA, ZIPMA, MAS1, MAS2,
 COUNTRYINC, STPRINC, EIN, FORMER, CHANGED,
 AFS, WKSI, FYE, FORM, PERIOD, FY, FP,
 FILED, ACCEPTED, PREVRPT, DETAIL, INSTANCE, NCIKS, ACIKS,
 SOURCE_QUARTER, SOURCE_FILE_NAME)
FROM (
    SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,$32,$33,$34,$35,$36,
        REGEXP_SUBSTR(METADATA$FILENAME, '[0-9]{4}q[1-4]'), METADATA$FILENAME
    FROM @SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE
)
PATTERN = '.*sub[.]txt.*';

COPY INTO SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
(ADSH, TAG, VERSION, DDATE, QTRS, UOM, SEGMENTS, COREG, VALUE, FOOTNOTE,
 SOURCE_QUARTER, SOURCE_FILE_NAME)
FROM (
    SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,
        REGEXP_SUBSTR(METADATA$FILENAME, '[0-9]{4}q[1-4]'), METADATA$FILENAME
    FROM @SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE
)
PATTERN = '.*num[.]txt.*';

COPY INTO SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_TAG_DEFINITIONS
(TAG, VERSION, CUSTOM, ABSTRACT, DATATYPE, IORD, CRDR, TLABEL, DOC,
 SOURCE_QUARTER, SOURCE_FILE_NAME)
FROM (
    SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,
        REGEXP_SUBSTR(METADATA$FILENAME, '[0-9]{4}q[1-4]'), METADATA$FILENAME
    FROM @SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE
)
PATTERN = '.*tag[.]txt.*';

COPY INTO SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_STATEMENT_PRESENTATION
(ADSH, REPORT, LINE, STMT, INPTH, RFILE, TAG, VERSION, PLABEL, NEGATING,
 SOURCE_QUARTER, SOURCE_FILE_NAME)
FROM (
    SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,
        REGEXP_SUBSTR(METADATA$FILENAME, '[0-9]{4}q[1-4]'), METADATA$FILENAME
    FROM @SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SEC_QUARTERLY_FILES_LANDING_STAGE
)
PATTERN = '.*pre[.]txt.*';

-- Confirms the fix: all four bronze tables now show 2025q3, 2025q4, 2026q1 and 2026q2.
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

-- Bronze now has the new quarters, but Silver and Gold are still Dynamic Tables on a 1 day lag,
-- so refresh them manually instead of waiting - same pattern as the earlier migration above.
-- Refresh Silver first, because Gold reads from Silver.
ALTER DYNAMIC TABLE SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS REFRESH;

ALTER DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_PROFITABILITY REFRESH;
ALTER DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_FINANCIAL_POSITION REFRESH;
ALTER DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_FILING REFRESH;

-- Result: each refresh reported new inserted rows (profitability +8,642, financial position +14,732,
-- filing +25,468), and the totals below confirm the three new quarters made it all the way to gold.
SELECT 'FACT_QUARTERLY_PROFITABILITY' AS TABLE_NAME, COUNT(*) FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_PROFITABILITY
UNION ALL SELECT 'FACT_QUARTERLY_FINANCIAL_POSITION', COUNT(*) FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_FINANCIAL_POSITION
UNION ALL SELECT 'FACT_FILING', COUNT(*) FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_FILING;

