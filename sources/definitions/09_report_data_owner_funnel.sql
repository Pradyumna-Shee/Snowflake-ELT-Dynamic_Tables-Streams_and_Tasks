-- 09_report_data_owner_funnel.sql
-- Data owner view: how many bronze rows survive each silver filter, one step at a time.
-- For the data owner role only, not for the other audiences.
-- Each row is one filter step. ROW_COUNT is how many rows are left after that step.

DEFINE SECURE VIEW SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_DATA_OWNER_ROW_FUNNEL
AS
WITH bronze_count AS (
    SELECT COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
),
after_parent_company AS (
    SELECT COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
    WHERE NULLIF(COREG, '') IS NULL
),
after_no_segments AS (
    SELECT COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
    WHERE NULLIF(COREG, '') IS NULL
      AND NULLIF(SEGMENTS, '') IS NULL
),
after_usd_only AS (
    SELECT COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
    WHERE NULLIF(COREG, '') IS NULL
      AND NULLIF(SEGMENTS, '') IS NULL
      AND UOM = 'USD'
),
after_valid_number AS (
    SELECT COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
    WHERE NULLIF(COREG, '') IS NULL
      AND NULLIF(SEGMENTS, '') IS NULL
      AND UOM = 'USD'
      AND TRY_TO_NUMBER(VALUE, 28, 4) IS NOT NULL
),
silver_count AS (
    SELECT COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS
),
gold_profitability_count AS (
    SELECT COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_PROFITABILITY
)
SELECT 1 AS STEP_NUMBER, 'Bronze: all reported financial values'                          AS FILTER_STEP, ROW_COUNT FROM bronze_count
UNION ALL
SELECT 2, 'Parent company only (COREG blank)',                                            ROW_COUNT FROM after_parent_company
UNION ALL
SELECT 3, 'No segment breakdowns (SEGMENTS blank)',                                       ROW_COUNT FROM after_no_segments
UNION ALL
SELECT 4, 'US dollars only',                                                              ROW_COUNT FROM after_usd_only
UNION ALL
SELECT 5, 'Value is a valid number',                                                      ROW_COUNT FROM after_valid_number
UNION ALL
SELECT 6, 'Silver: joined to filing and tag, standard tags only, not later amended',      ROW_COUNT FROM silver_count
UNION ALL
SELECT 7, 'Gold: profitability fact (10-Q, one quarter, revenue and net income filters)', ROW_COUNT FROM gold_profitability_count
ORDER BY STEP_NUMBER;

GRANT SELECT ON VIEW SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_DATA_OWNER_ROW_FUNNEL TO ROLE SEC_DATA_OWNER_ROLE;