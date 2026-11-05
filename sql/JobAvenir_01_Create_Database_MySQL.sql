-- ============================================================================
-- JobAvenir | ADT Milestone 2 | FILE 1 OF 2
-- MySQL Community Server 8.0+ | Run in MySQL Workbench
-- PURPOSE: Create the database, 7 CSV staging tables and 8 core tables.
-- ============================================================================
-- INSTRUCTIONS
--  1. Open MySQL Workbench and connect to your MySQL server.
--  2. File > Open SQL Script > this file.
--  3. Execute the entire script (lightning-bolt icon).
--  4. Refresh SCHEMAS > jobavenir_db > Tables (15 tables).
--  5. Import the seven CLEANED CSV files into the stg_* tables
--     (see JobAvenir_MySQL_README.txt for which file goes where).
--  6. ONLY THEN execute JobAvenir_02_Load_and_Analyze_MySQL.sql.
--
-- IMPORTANT: This is MySQL syntax, NOT Snowflake SQL.
-- CREATE TABLE IF NOT EXISTS will not alter previously created table designs.
-- The skills tables were redesigned on 5 Nov 2026 (one skills table with a
-- skill_category field). A jobavenir_db built with the older scripts must be
-- rebuilt once: DROP DATABASE jobavenir_db; then run this file again. That
-- only removes your local copy; everything is rebuilt from the CSVs.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS jobavenir_db
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE jobavenir_db;

SELECT DATABASE() AS selected_database;

-- ============================================================================
-- PART A. STAGING TABLES (one per cleaned CSV file)
-- These are landing tables: each one matches its CSV column for column, so
-- the Workbench Import Wizard can load it directly. All columns are
-- permissive text so source values and blanks can be inspected before the
-- strictly typed core tables are loaded by File 2.
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
-- Here skill_category is O*NET's technology type (e.g. 'Spreadsheet software').
-- File 2 stores it as occupation_technology_skills.technology_type.
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

-- CSV: essential_skills_clean.csv   (O*NET Basic Skills, element IDs 2.A.*)
-- CSV: transferable_skills_clean.csv (O*NET Cross-Functional Skills, 2.B.*)
-- Both files have the same 15 headers:
--   occupation_id, occupation_title, element_id, skill_name, scale_id,
--   scale_name, data_value, sample_size, standard_error, lower_ci_bound,
--   upper_ci_bound, recommend_suppress, not_relevant, date_updated,
--   domain_source
-- They stay in two staging tables (one per CSV) so the file a row came from
-- decides its skill_category in File 2.
CREATE TABLE IF NOT EXISTS stg_essential_skills (
  occupation_id      VARCHAR(20),
  occupation_title   VARCHAR(500),
  element_id         VARCHAR(20),
  skill_name         VARCHAR(255),
  scale_id           VARCHAR(3),
  scale_name         VARCHAR(50),
  data_value         VARCHAR(40),
  sample_size        VARCHAR(40),
  standard_error     VARCHAR(40),
  lower_ci_bound     VARCHAR(40),
  upper_ci_bound     VARCHAR(40),
  recommend_suppress VARCHAR(5),
  not_relevant       VARCHAR(5),
  date_updated       VARCHAR(10),
  domain_source      VARCHAR(30)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS stg_transferable_skills (
  occupation_id      VARCHAR(20),
  occupation_title   VARCHAR(500),
  element_id         VARCHAR(20),
  skill_name         VARCHAR(255),
  scale_id           VARCHAR(3),
  scale_name         VARCHAR(50),
  data_value         VARCHAR(40),
  sample_size        VARCHAR(40),
  standard_error     VARCHAR(40),
  lower_ci_bound     VARCHAR(40),
  upper_ci_bound     VARCHAR(40),
  recommend_suppress VARCHAR(5),
  not_relevant       VARCHAR(5),
  date_updated       VARCHAR(10),
  domain_source      VARCHAR(30)
) ENGINE=InnoDB;

-- ============================================================================
-- PART B. CORE RELATIONAL TABLES
-- PK = primary key; FK = foreign key. InnoDB ENFORCES these keys in MySQL.
-- VARCHAR identifiers preserve O*NET-SOC codes (e.g., 15-2051.00) and Jobicy IDs.
--
-- Skills design: every skill lives in ONE table (skills) with a
-- skill_category field. How a skill relates to an occupation differs by
-- category, so the links are kept in two tables:
--   occupation_technology_skills : Technology skills an occupation uses,
--                                  with Hot Technology / In Demand flags
--   occupation_skill_ratings     : Essential and Transferable skills,
--                                  rated for Importance and Level
-- Jobicy postings link to the same skills table through job_skills.
-- ============================================================================

-- 1. O*NET standardized occupations
CREATE TABLE IF NOT EXISTS occupations (
  occupation_id    VARCHAR(20) NOT NULL,
  occupation_title VARCHAR(500) NOT NULL,
  description      LONGTEXT NULL,
  PRIMARY KEY (occupation_id)
) ENGINE=InnoDB;

-- 2. All skills, one row per skill.
--    skill_category  : 'Technology'   = O*NET software/technology skills and
--                                       the technical keywords found in Jobicy
--                      'Essential'    = O*NET Basic Skills (e.g. Writing)
--                      'Transferable' = O*NET Cross-Functional Skills
--                                       (e.g. Complex Problem Solving)
--    onet_element_id : O*NET's ID for Essential/Transferable skills
--                      (e.g. 2.A.1.a); NULL for Technology skills.
--    skill_source    : 'O*NET', or 'Jobicy' for a keyword not in O*NET under
--                      that exact name (e.g. 'SQL'). A later skill-alias step
--                      can link these to their O*NET names.
CREATE TABLE IF NOT EXISTS skills (
  skill_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  skill_name      VARCHAR(500) NOT NULL,
  skill_category  VARCHAR(20)  NOT NULL,
  onet_element_id VARCHAR(20)  NULL,
  skill_source    VARCHAR(20)  NOT NULL DEFAULT 'O*NET',
  PRIMARY KEY (skill_id),
  UNIQUE KEY uq_skills_name_category (skill_name, skill_category),
  UNIQUE KEY uq_skills_onet_element (onet_element_id),
  KEY idx_skills_category (skill_category),
  CONSTRAINT chk_skills_category
    CHECK (skill_category IN ('Technology', 'Essential', 'Transferable')),
  CONSTRAINT chk_skills_source
    CHECK (skill_source IN ('O*NET', 'Jobicy'))
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

-- 4. Technology skills used in each occupation (O*NET Technology Skills).
--    technology_type is O*NET's grouping for the tool in THIS occupation
--    (e.g. 'Spreadsheet software'). It belongs to the link, not the skill:
--    151 tools are grouped differently in different occupations.
--    Rows here should point to skills with skill_category = 'Technology'.
CREATE TABLE IF NOT EXISTS occupation_technology_skills (
  occupation_id   VARCHAR(20) NOT NULL,
  skill_id        BIGINT UNSIGNED NOT NULL,
  technology_type VARCHAR(500) NULL,
  hot_technology  TINYINT(1) NOT NULL DEFAULT 0,
  in_demand       TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (occupation_id, skill_id),
  KEY idx_occtech_skill (skill_id),
  CONSTRAINT fk_occtech_occupation FOREIGN KEY (occupation_id)
    REFERENCES occupations (occupation_id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_occtech_skill FOREIGN KEY (skill_id)
    REFERENCES skills (skill_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 5. Essential and Transferable skill ratings per occupation (one table).
--    One row = one occupation x one skill x one scale.
--    scale_id: IM = Importance (1-5), LV = Level (0-7). The two scales are
--    separate rows and must not be averaged together.
--    Skill name and category come from skills; occupation title from
--    occupations (JOIN), so neither is repeated here.
--    date_updated is O*NET's month of update, stored as 'YYYY-MM' (the two
--    CSVs write it differently: '08/2026' and 'Aug-26').
--    not_relevant is only filled for the Level scale.
CREATE TABLE IF NOT EXISTS occupation_skill_ratings (
  occupation_id      VARCHAR(20) NOT NULL,
  skill_id           BIGINT UNSIGNED NOT NULL,
  scale_id           CHAR(2) NOT NULL,
  data_value         DECIMAL(5,2) NULL,
  sample_size        INT UNSIGNED NULL,
  standard_error     DECIMAL(7,4) NULL,
  lower_ci_bound     DECIMAL(7,4) NULL,
  upper_ci_bound     DECIMAL(7,4) NULL,
  recommend_suppress CHAR(1) NULL,
  not_relevant       CHAR(1) NULL,
  date_updated       CHAR(7) NULL,
  domain_source      VARCHAR(30) NULL,
  PRIMARY KEY (occupation_id, skill_id, scale_id),
  KEY idx_ratings_skill (skill_id, scale_id),
  CONSTRAINT fk_ratings_occupation FOREIGN KEY (occupation_id)
    REFERENCES occupations (occupation_id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_ratings_skill FOREIGN KEY (skill_id)
    REFERENCES skills (skill_id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT chk_ratings_scale
    CHECK (scale_id IN ('IM', 'LV')),
  CONSTRAINT chk_ratings_suppress
    CHECK (recommend_suppress IS NULL OR recommend_suppress IN ('Y', 'N')),
  CONSTRAINT chk_ratings_relevant
    CHECK (not_relevant IS NULL OR not_relevant IN ('Y', 'N'))
) ENGINE=InnoDB;

-- 6. Companies extracted from Jobicy postings
CREATE TABLE IF NOT EXISTS companies (
  company_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  company_name VARCHAR(500) NOT NULL,
  PRIMARY KEY (company_id),
  UNIQUE KEY uq_companies_name (company_name)
) ENGINE=InnoDB;

-- 7. Actual Jobicy jobs. occupation_id starts NULL until title matching.
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

-- 8. Skills extracted from Jobicy descriptions (many-to-many jobs <-> skills)
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
-- VERIFY SUCCESS: 7 staging tables + 8 core tables = 15 tables
-- ============================================================================
SHOW TABLES FROM jobavenir_db;
SHOW CREATE TABLE skills;
SHOW CREATE TABLE occupation_skill_ratings;
SELECT 'DATABASE SCHEMA CREATED: import the seven CSVs into stg_* tables next' AS status;
