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

-- Manual refresh: use after loading new bronze data or changing a definition, instead of waiting for the 1 day lag.
-- Refresh Silver first, because Gold reads from Silver.
ALTER DYNAMIC TABLE SEC_FINANCIAL_DATA.SILVER_SEC_INTEGRATED_FILINGS.SEC_FINANCIAL_FACTS_WITH_FILING_AND_TAG_DETAILS REFRESH;

ALTER DYNAMIC TABLE SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.SEC_COMPANY_QUARTERLY_PROFITABILITY REFRESH;



