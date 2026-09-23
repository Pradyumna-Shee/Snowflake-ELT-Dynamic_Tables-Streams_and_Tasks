-- 09_report_data_owner_funnel.sql
-- Data owner view: how many bronze rows survive each silver filter, one step at a time, per quarter.
-- For the data owner role only, not for the other audiences.
-- Each row is one filter step for one quarter. ROW_COUNT is how many rows are left after that step.
-- Today this shows one quarter (2025q3). More rows appear automatically as more quarters are loaded.

-- DROP VIEW SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_DATA_OWNER_ROW_FUNNEL;

DEFINE SECURE VIEW SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_DATA_OWNER_ROW_FUNNEL
AS
WITH bronze_count AS (
    SELECT SOURCE_QUARTER, COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
    GROUP BY SOURCE_QUARTER
),
after_parent_company AS (
    SELECT SOURCE_QUARTER, COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
    WHERE NULLIF(COREG, '') IS NULL
    GROUP BY SOURCE_QUARTER
),
after_no_segments AS (
    SELECT SOURCE_QUARTER, COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
    WHERE NULLIF(COREG, '') IS NULL
      AND NULLIF(SEGMENTS, '') IS NULL
    GROUP BY SOURCE_QUARTER
),
after_usd_only AS (
    SELECT SOURCE_QUARTER, COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
    WHERE NULLIF(COREG, '') IS NULL
      AND NULLIF(SEGMENTS, '') IS NULL
      AND UOM = 'USD'
    GROUP BY SOURCE_QUARTER
),
after_valid_number AS (
    SELECT SOURCE_QUARTER, COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.BRONZE_SEC_FILINGS_STAGING.SOURCE_SEC_FINANCIAL_VALUES
    WHERE NULLIF(COREG, '') IS NULL
      AND NULLIF(SEGMENTS, '') IS NULL
      AND UOM = 'USD'
      AND TRY_TO_NUMBER(VALUE, 28, 4) IS NOT NULL
    GROUP BY SOURCE_QUARTER
),
silver_count AS (
    SELECT SOURCE_QUARTER, COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS
    GROUP BY SOURCE_QUARTER
),
gold_profitability_count AS (
    SELECT SOURCE_QUARTER, COUNT(*) AS ROW_COUNT
    FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_PROFITABILITY
    GROUP BY SOURCE_QUARTER
)
SELECT 1 AS STEP_NUMBER, 'Bronze: all reported financial values'                          AS FILTER_STEP, SOURCE_QUARTER, ROW_COUNT FROM bronze_count
UNION ALL
SELECT 2, 'Parent company only (COREG blank)',                                            SOURCE_QUARTER, ROW_COUNT FROM after_parent_company
UNION ALL
SELECT 3, 'No segment breakdowns (SEGMENTS blank)',                                       SOURCE_QUARTER, ROW_COUNT FROM after_no_segments
UNION ALL
SELECT 4, 'US dollars only',                                                              SOURCE_QUARTER, ROW_COUNT FROM after_usd_only
UNION ALL
SELECT 5, 'Value is a valid number',                                                      SOURCE_QUARTER, ROW_COUNT FROM after_valid_number
UNION ALL
SELECT 6, 'Silver: joined to filing and tag, standard tags only, not later amended',      SOURCE_QUARTER, ROW_COUNT FROM silver_count
UNION ALL
SELECT 7, 'Gold: profitability fact (10-Q, one quarter, revenue and net income filters)', SOURCE_QUARTER, ROW_COUNT FROM gold_profitability_count
ORDER BY SOURCE_QUARTER, STEP_NUMBER;

GRANT SELECT ON VIEW SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_DATA_OWNER_ROW_FUNNEL TO ROLE SEC_DATA_OWNER_ROLE;