-- ============================================================================
-- JobAvenir | ADT Milestone 2 | FILE 1 OF 2
-- MySQL Community Server 8.0+ | Run in MySQL Workbench
-- PURPOSE: Create database + 5 CSV staging tables + 7 relational (core) tables.
-- ============================================================================
-- INSTRUCTIONS
--  1. Open MySQL Workbench and connect to your MySQL Community Server.
--  2. File > Open SQL Script > this file.
--  3. Execute the entire script (lightning-bolt icon).
--  4. Refresh SCHEMAS > jobavenir_db > Tables.
--  5. Import your five CLEANED CSV files into stg_* tables via Workbench's
--     Table Data Import Wizard (see JobAvenir_MySQL_README.txt).
--  6. ONLY THEN execute JobAvenir_02_Load_and_Analyze_MySQL.sql.
--
-- IMPORTANT: This is MySQL syntax, NOT Snowflake SQL.
-- CREATE TABLE IF NOT EXISTS will not alter previously created table designs.
-- If jobavenir_db already exists without the Jobicy URL/salary/level columns,
-- run JobAvenir_01b_Add_Jobicy_Fields_MySQL.sql once to add them.
-- Do not use DROP DATABASE, DROP TABLE, or foreign_key_checks=0 on your work.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS jobavenir_db
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE jobavenir_db;

SELECT DATABASE() AS selected_database;

-- ============================================================================
-- PART A. STAGING TABLES (one per cleaned CSV file)
-- These are temporary landing tables in the logical sense, but are kept as
-- regular tables so you can reproduce loading and show original cleaned rows.
-- All columns are deliberately permissive to inspect source records first.
-- ============================================================================

-- CSV: occupations_clean.csv
-- Expected headers: occupation_id, occupation_title, description
CREATE TABLE IF NOT EXISTS stg_occupations (
  occupation_id    VARCHAR(20),
  occupation_title VARCHAR(500),
  description      LONGTEXT
) ENGINE=InnoDB;

-- CSV: software_skills_clean.csv
-- Expected headers: occupation_id, occupation_title, skill_name, element_id,
--                   skill_category, hot_technology, in_demand
CREATE TABLE IF NOT EXISTS stg_software_skills (
  occupation_id    VARCHAR(20),
  occupation_title VARCHAR(500),
  skill_name       VARCHAR(500),
  element_id       VARCHAR(50),
  skill_category   VARCHAR(500),
  hot_technology   VARCHAR(10),
  in_demand        VARCHAR(10)
) ENGINE=InnoDB;

-- CSV: job_titles_clean.csv
-- Expected headers: occupation_id, occupation_title, job_title, short_title, source
CREATE TABLE IF NOT EXISTS stg_job_titles (
  occupation_id    VARCHAR(20),
  occupation_title VARCHAR(500),
  job_title        VARCHAR(500),
  short_title      VARCHAR(500),
  `source`         VARCHAR(100)
) ENGINE=InnoDB;

-- CSV: jobicy_jobs_clean.csv
-- Expected headers: job_id, job_title, company_name, location,
--                   description_clean, publication_date, job_url, job_level,
--                   job_industry, salary_min, salary_max, salary_currency,
--                   salary_period, searched_role, collected_at, last_seen_at
CREATE TABLE IF NOT EXISTS stg_jobicy_postings (
  job_id            VARCHAR(100),
  job_title         VARCHAR(500),
  company_name      VARCHAR(500),
  location          VARCHAR(500),
  description_clean LONGTEXT,
  publication_date  VARCHAR(100),
  job_url           VARCHAR(1000),
  job_level         VARCHAR(100),
  job_industry      VARCHAR(500),
  salary_min        VARCHAR(50),
  salary_max        VARCHAR(50),
  salary_currency   VARCHAR(10),
  salary_period     VARCHAR(20),
  searched_role     VARCHAR(100),
  collected_at      VARCHAR(100),
  last_seen_at      VARCHAR(100)
) ENGINE=InnoDB;

-- CSV: job_skills_clean.csv (extracted from Jobicy job descriptions)
-- Expected headers: job_id, skill_name
CREATE TABLE IF NOT EXISTS stg_job_skills (
  job_id      VARCHAR(100),
  skill_name  VARCHAR(500)
) ENGINE=InnoDB;

-- ============================================================================
-- PART B. CORE RELATIONAL TABLES
-- PK = primary key; FK = foreign key. InnoDB ENFORCES these keys in MySQL.
-- VARCHAR identifiers preserve O*NET-SOC codes (e.g., 15-2051.00) and Jobicy IDs.
-- ============================================================================

-- 1. O*NET standardized occupations
CREATE TABLE IF NOT EXISTS occupations (
  occupation_id    VARCHAR(20) NOT NULL,
  occupation_title VARCHAR(500) NOT NULL,
  description      LONGTEXT NULL,
  PRIMARY KEY (occupation_id)
) ENGINE=InnoDB;

-- 2. Distinct technical software/skills. Avoid repeating "Python" per occupation.
CREATE TABLE IF NOT EXISTS skills (
  skill_id       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  skill_name     VARCHAR(500) NOT NULL,
  skill_category VARCHAR(500) NULL,
  PRIMARY KEY (skill_id),
  UNIQUE KEY uq_skills_name (skill_name)
) ENGINE=InnoDB;

-- 3. O*NET alternative titles, one occupation can have many aliases
CREATE TABLE IF NOT EXISTS job_titles (
  title_id       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  occupation_id  VARCHAR(20) NOT NULL,
  job_title      VARCHAR(500) NOT NULL,
  short_title    VARCHAR(500) NULL,
  source_code    VARCHAR(100) NOT NULL,
  PRIMARY KEY (title_id),
  UNIQUE KEY uq_occ_jobtitle_source (occupation_id, job_title, source_code),
  KEY idx_job_titles_title (job_title),
  CONSTRAINT fk_jobtitles_occupation FOREIGN KEY (occupation_id)
    REFERENCES occupations (occupation_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 4. O*NET occupation/software relationships. Element ID distinguishes
--    O*NET software categories when the same software appears more than once.
CREATE TABLE IF NOT EXISTS occupation_skills (
  occupation_id  VARCHAR(20) NOT NULL,
  skill_id       BIGINT UNSIGNED NOT NULL,
  element_id     VARCHAR(50) NOT NULL,
  element_name   VARCHAR(500) NULL,
  hot_technology TINYINT(1) NOT NULL DEFAULT 0,
  in_demand      TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (occupation_id, skill_id, element_id),
  KEY idx_occskills_skill (skill_id),
  CONSTRAINT fk_occskills_occupation FOREIGN KEY (occupation_id)
    REFERENCES occupations (occupation_id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_occskills_skill FOREIGN KEY (skill_id)
    REFERENCES skills (skill_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 5. Companies extracted from Jobicy postings
CREATE TABLE IF NOT EXISTS companies (
  company_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  company_name VARCHAR(500) NOT NULL,
  PRIMARY KEY (company_id),
  UNIQUE KEY uq_companies_name (company_name)
) ENGINE=InnoDB;

-- 6. Actual Jobicy jobs. occupation_id starts NULL until title matching.
-- job_geo describes remote geographic eligibility, NOT a verified US state.
-- job_url links to the original Jobicy page (Jobicy asks for credit + link).
-- Salary columns are NULL when the employer listed no pay range.
-- searched_role = first Jobicy search tag that returned the posting.
-- collected_at / last_seen_at = first and latest pull that saw the posting.
CREATE TABLE IF NOT EXISTS job_postings (
  job_id          VARCHAR(100) NOT NULL,
  job_title       VARCHAR(500) NOT NULL,
  company_id      BIGINT UNSIGNED NULL,
  occupation_id   VARCHAR(20) NULL,
  role_category   VARCHAR(100) NOT NULL DEFAULT 'Other Tech',
  job_geo         VARCHAR(500) NULL,
  job_description LONGTEXT NULL,
  published_at    DATETIME NULL,
  job_url         VARCHAR(1000) NULL,
  job_level       VARCHAR(100) NULL,
  job_industry    VARCHAR(500) NULL,
  salary_min      DECIMAL(12,2) NULL,
  salary_max      DECIMAL(12,2) NULL,
  salary_currency VARCHAR(10) NULL,
  salary_period   VARCHAR(20) NULL,
  searched_role   VARCHAR(100) NULL,
  collected_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                                  ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (job_id),
  KEY idx_postings_company (company_id),
  KEY idx_postings_occupation (occupation_id),
  KEY idx_postings_role (role_category),
  CONSTRAINT fk_postings_company FOREIGN KEY (company_id)
    REFERENCES companies (company_id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_postings_occupation FOREIGN KEY (occupation_id)
    REFERENCES occupations (occupation_id)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

-- 7. Skills extracted from Jobicy descriptions (many-to-many jobs <-> skills)
CREATE TABLE IF NOT EXISTS job_skills (
  job_id            VARCHAR(100) NOT NULL,
  skill_id          BIGINT UNSIGNED NOT NULL,
  extraction_method VARCHAR(50) NOT NULL DEFAULT 'keyword_match',
  PRIMARY KEY (job_id, skill_id),
  KEY idx_jobskills_skill (skill_id),
  CONSTRAINT fk_jobskills_job FOREIGN KEY (job_id)
    REFERENCES job_postings (job_id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_jobskills_skill FOREIGN KEY (skill_id)
    REFERENCES skills (skill_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ============================================================================
-- VERIFY SUCCESS: 5 staging tables + 7 core tables = 12 tables
-- ============================================================================
SHOW TABLES FROM jobavenir_db;
SHOW CREATE TABLE occupations;
SHOW CREATE TABLE job_postings;
SELECT 'DATABASE SCHEMA CREATED: import five CSVs into stg_* tables next' AS status;
