-- 04_security_role_checks.sql
-- Checks that each role sees what it should and is blocked from the rest.
-- Run one statement at a time. Where it says "expect error", an error is the pass.
-- Expected counts are for the 2025q3 data and change when more quarters are loaded.

USE SECONDARY ROLES NONE;

-- ============================================================
-- Analyst: all divisions, dollar columns included
-- ============================================================
USE ROLE SEC_ANALYST_ROLE;
USE WAREHOUSE SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE;

-- expect 9
SELECT COUNT(DISTINCT INDUSTRY_DIVISION) AS DIVISIONS_SEEN
FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY;

-- expect a number, dollar column is there
SELECT SUM(TOTAL_REVENUE_USD) AS TOTAL_REVENUE_USD
FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY;
-- 4864075467047.0000

-- expect error, analyst cannot read the fact table directly
SELECT COUNT(*) FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_PROFITABILITY;
-- SQL compilation error: Object 'SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_PROFITABILITY' does not exist or not authorized.


-- expect error, nobody edits their own access
SELECT COUNT(*) FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.ROLE_INDUSTRY_ACCESS;
-- SQL compilation error: Object 'SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.ROLE_INDUSTRY_ACCESS' does not exist or not authorized.

-- ============================================================
-- Industry analyst: only Manufacturing and Retail Trade
-- ============================================================
USE ROLE SEC_INDUSTRY_ANALYST_ROLE;
USE WAREHOUSE SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE;

-- expect Manufacturing and Retail Trade, nothing else
SELECT DISTINCT INDUSTRY_DIVISION
FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY;
--  INDUSTRY_DIVISION
--  Retail Trade
--  Manufacturing

-- same two divisions in the public view
SELECT DISTINCT INDUSTRY_DIVISION
FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY_PUBLIC;
--  INDUSTRY_DIVISION
--  Manufacturing
--  Retail Trade


-- ============================================================
-- Public reporter: public view only, no dollars
-- ============================================================
USE ROLE SEC_PUBLIC_REPORTER_ROLE;
USE WAREHOUSE SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE;

-- expect 9
SELECT COUNT(DISTINCT INDUSTRY_DIVISION) AS DIVISIONS_SEEN
FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY_PUBLIC;

-- expect error, the dollar column is not in the public view
SELECT TOTAL_REVENUE_USD
FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY_PUBLIC;
--  QL compilation error: error line 64 at position 7 invalid identifier 'TOTAL_REVENUE_USD

-- expect error, no access to the full view
SELECT COUNT(*) FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY;
--  SQL compilation error: Object 'SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.REPORT_INDUSTRY_PROFITABILITY' does not exist or not authorized.

-- expect error, no access to the fact table
SELECT COUNT(*) FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_PROFITABILITY;
--  SQL compilation error: Object 'SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_PROFITABILITY' does not exist or not authorized.

-- ============================================================
-- Data owner: reads the gold tables
-- ============================================================
USE ROLE SEC_DATA_OWNER_ROLE;
USE WAREHOUSE SEC_FINANCIAL_DATA_PIPELINE_WAREHOUSE;

-- expect 2727 (will fail until the owner gets SELECT on the gold tables, see note)
SELECT COUNT(*) FROM SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_PROFITABILITY;
--  SQL compilation error: Object 'SEC_FINANCIAL_DATA.GOLD_SEC_ANALYTICS_REPORTING.FACT_QUARTERLY_PROFITABILITY' does not exist or not authorized.

-- back to the project owner
USE ROLE ACCOUNTADMIN;
