-- ============================================================================
-- JobAvenir | ADT Milestone 2 | FILE 1b (run ONCE on an EXISTING database)
-- MySQL Community Server 8.0+ | Run in MySQL Workbench
-- PURPOSE: Add the Jobicy fields that the updated cleaning notebook now keeps:
--          job URL, job level, industry, salary range, searched_role (the
--          Jobicy search tag), and first/last time a posting was seen.
-- ============================================================================
-- WHEN TO RUN
--  * Run this file once if jobavenir_db was created with the earlier version
--    of JobAvenir_01_Create_Database_MySQL.sql (CREATE TABLE IF NOT EXISTS
--    does not add columns to tables that already exist).
--  * Skip it on a brand-new database: File 1 now creates these columns.
--  * MySQL 8.0 has no ADD COLUMN IF NOT EXISTS. If you get error 1060
--    "Duplicate column name", the columns are already there; nothing to do.
--
-- AFTER RUNNING
--  1. Re-run notebooks/02_Jobicy_Data_Collection.ipynb (writes the new CSVs).
--  2. Re-import the Jobicy CSVs with notebooks/importing_jobicy_data_into_MySql.ipynb
--     (REPLACE_STAGING = 1 replaces the old staging rows).
--  3. Run JobAvenir_02_Load_and_Analyze_MySQL.sql again.
-- ============================================================================

USE jobavenir_db;

-- Staging table: permissive text columns, same as the rest of staging
ALTER TABLE stg_jobicy_postings
  ADD COLUMN job_url         VARCHAR(1000) NULL AFTER publication_date,
  ADD COLUMN job_level       VARCHAR(100)  NULL AFTER job_url,
  ADD COLUMN job_industry    VARCHAR(500)  NULL AFTER job_level,
  ADD COLUMN salary_min      VARCHAR(50)   NULL AFTER job_industry,
  ADD COLUMN salary_max      VARCHAR(50)   NULL AFTER salary_min,
  ADD COLUMN salary_currency VARCHAR(10)   NULL AFTER salary_max,
  ADD COLUMN salary_period   VARCHAR(20)   NULL AFTER salary_currency,
  ADD COLUMN searched_role   VARCHAR(100)  NULL AFTER salary_period,
  ADD COLUMN collected_at    VARCHAR(100)  NULL AFTER searched_role,
  ADD COLUMN last_seen_at    VARCHAR(100)  NULL AFTER collected_at;

-- Core table: typed columns. collected_at / last_seen_at already exist here.
ALTER TABLE job_postings
  ADD COLUMN job_url         VARCHAR(1000) NULL AFTER published_at,
  ADD COLUMN job_level       VARCHAR(100)  NULL AFTER job_url,
  ADD COLUMN job_industry    VARCHAR(500)  NULL AFTER job_level,
  ADD COLUMN salary_min      DECIMAL(12,2) NULL AFTER job_industry,
  ADD COLUMN salary_max      DECIMAL(12,2) NULL AFTER salary_min,
  ADD COLUMN salary_currency VARCHAR(10)   NULL AFTER salary_max,
  ADD COLUMN salary_period   VARCHAR(20)   NULL AFTER salary_currency,
  ADD COLUMN searched_role   VARCHAR(100)  NULL AFTER salary_period;

-- VERIFY: both tables should list the new columns
SHOW COLUMNS FROM stg_jobicy_postings;
SHOW COLUMNS FROM job_postings;
SELECT 'NEW JOBICY COLUMNS ADDED: re-import the Jobicy CSVs, then run File 2' AS status;
