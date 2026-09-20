-- 00_github_integration_setup.sql
-- SEC Financial Data Pipeline
-- Connect Snowflake to GitHub, so project files can be edited in Snowsight and pushed to the repo.
-- Run each statement one at a time (select it, then Ctrl+Enter), with the ACCOUNTADMIN role.

-- ============================================================
-- Steps on GitHub (done in the browser and on the computer)
-- ============================================================
-- 1. Create a new empty repository on GitHub (https://github.com/new).
--      Name: Snowflake-ELT-Dynamic_Tables-Streams_and_Tasks, set to Private.

-- 2. Push a first commit from your computer (git init, git add, git commit, git remote add origin, git push).
--      Why: a Git workspace in Snowflake cannot be created from an empty repository. It needs at least one branch.
--      Add a .gitignore first, so the large SEC data files are never pushed.

-- 3. Create a fine-grained personal access token (GitHub > Settings > Developer settings > Personal access tokens).
--      Repository access: only this repository.
--      Permissions: Contents = Read and write. Metadata = Read-only (GitHub adds it by itself and it cannot be changed).
--      Expiration: 90 days.
--      Why: Snowflake uses the token to log in to GitHub instead of a password.
--      Copy the token when it is shown. GitHub never shows it again. Never put it in the repo or share it.

-- ============================================================
-- Steps in Snowflake (SQL)
-- ============================================================

-- 4. Schema: a place to keep the secret, separate from the pipeline schemas.
CREATE SCHEMA IF NOT EXISTS SEC_FINANCIAL_ANALYTICS.GITHUB_CONNECTION;

-- 5. Secret: stores the GitHub username and the token, so the token is not typed in later steps.
--    Replace PASTE_YOUR_TOKEN_HERE with your own token when you run this. Never save the real token in a file.
CREATE OR REPLACE SECRET SEC_FINANCIAL_ANALYTICS.GITHUB_CONNECTION.GITHUB_PERSONAL_ACCESS_TOKEN_SECRET
  TYPE = PASSWORD
  USERNAME = 'Pradyumna-Shee'
  PASSWORD = 'PASTE_YOUR_TOKEN_HERE';       --  PASTE YOUR TOKEN HERE

-- 6. API integration: allows Snowflake to talk to GitHub, only for this account's URLs and only with the secret above.
CREATE OR REPLACE API INTEGRATION GITHUB_API_INTEGRATION
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/Pradyumna-Shee')
  ALLOWED_AUTHENTICATION_SECRETS = (SEC_FINANCIAL_ANALYTICS.GITHUB_CONNECTION.GITHUB_PERSONAL_ACCESS_TOKEN_SECRET)
  ENABLED = TRUE;

-- ============================================================
-- Steps in Snowsight (no SQL, done in the browser)
-- ============================================================
-- 7. In Workspaces, click the + icon (Create workspace) and choose Git workspace.
-- 8. Fill in the form:
--      Repository URL: https://github.com/Pradyumna-Shee/Snowflake-ELT-Dynamic_Tables-Streams_and_Tasks
--      API integration: GITHUB_API_INTEGRATION (selected by itself)
--      Authentication: Personal access token
--      Database and schema: SEC_FINANCIAL_ANALYTICS and GITHUB_CONNECTION
--      Secret: GITHUB_PERSONAL_ACCESS_TOKEN_SECRET (choose the existing one, do not create a new one)
--    Click Create. The workspace opens with the files from the repo.
-- 9. To save work to GitHub: edit the files, open the Changes tab, write a commit message and click Push.

-- ============================================================
-- When the token expires (after 90 days)
-- ============================================================
-- Push and pull will fail with a login error. Create a new token on GitHub (step 3), then update the secret:
-- ALTER SECRET SEC_FINANCIAL_ANALYTICS.GITHUB_CONNECTION.GITHUB_PERSONAL_ACCESS_TOKEN_SECRET
--   SET PASSWORD = 'PASTE_YOUR_NEW_TOKEN_HERE';