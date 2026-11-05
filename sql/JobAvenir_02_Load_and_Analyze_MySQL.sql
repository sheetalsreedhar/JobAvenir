-- ============================================================================
-- JobAvenir | ADT Milestone 2 | FILE 2 OF 2
-- MySQL Community Server 8.0+ | Run in MySQL Workbench
-- PURPOSE: Verify staging CSVs, populate normalized tables, validate integrity,
--          create Market Skill Demand VIEW, show analytical queries and CRUD.
-- ============================================================================
-- BEFORE RUNNING:
--   [ ] Ran JobAvenir_01_Create_Database_MySQL.sql successfully.
--   [ ] On a database created before the URL/salary/level columns existed,
--       ran JobAvenir_01b_Add_Jobicy_Fields_MySQL.sql once.
--   [ ] Imported all FIVE cleaned CSV files into matching stg_* tables:
--       occupations_clean.csv      -> stg_occupations
--       software_skills_clean.csv  -> stg_software_skills
--       job_titles_clean.csv       -> stg_job_titles
--       jobicy_jobs_clean.csv      -> stg_jobicy_postings
--       job_skills_clean.csv       -> stg_job_skills
--   [ ] Matched CSV column names and skipped the CSV header on import.
--   [ ] You can run individual SELECTs with the cursor on a statement.
--
-- This file is designed to be rerunnable on the *same imported staging data*:
-- unique keys/upserts prevent duplicate rows in core tables. Re-importing the
-- same CSVs into staging itself WILL duplicate staging rows; avoid that.
-- The role classification and occupation title mapping are best-effort,
-- require manual checks, and must not be represented as ground truth.
-- ============================================================================

USE jobavenir_db;

-- The Python export writes UTC times; store and show TIMESTAMP columns in UTC.
SET time_zone = '+00:00';

-- --------------------------------------------------------------------------
-- STEP 0. Confirm you actually imported data before proceeding.
-- Original O*NET file counts were 1016, 31821, 54269 before cleaning.
-- Jobicy API counts vary. Zero Jobicy rows means no market results yet.
-- --------------------------------------------------------------------------
SELECT 'stg_occupations' AS table_name, COUNT(*) AS row_count
  FROM stg_occupations
UNION ALL SELECT 'stg_software_skills', COUNT(*) FROM stg_software_skills
UNION ALL SELECT 'stg_job_titles', COUNT(*) FROM stg_job_titles
UNION ALL SELECT 'stg_jobicy_postings', COUNT(*) FROM stg_jobicy_postings
UNION ALL SELECT 'stg_job_skills', COUNT(*) FROM stg_job_skills;

-- VALIDATION BEFORE LOADING: unmatched O*NET occupation codes
SELECT 'software_skills' AS dataset, COUNT(*) AS unmatched_rows
FROM stg_software_skills s
LEFT JOIN stg_occupations o
  ON TRIM(s.occupation_id) = TRIM(o.occupation_id)
WHERE o.occupation_id IS NULL
UNION ALL
SELECT 'job_titles', COUNT(*)
FROM stg_job_titles t
LEFT JOIN stg_occupations o
  ON TRIM(t.occupation_id) = TRIM(o.occupation_id)
WHERE o.occupation_id IS NULL;

-- --------------------------------------------------------------------------
-- STEP 1. OCCUPATIONS: one row per O*NET-SOC code.
-- --------------------------------------------------------------------------
INSERT INTO occupations (occupation_id, occupation_title, description)
SELECT TRIM(s.occupation_id),
       MAX(TRIM(s.occupation_title)),
       MAX(NULLIF(TRIM(s.description), ''))
FROM stg_occupations s
WHERE NULLIF(TRIM(s.occupation_id), '') IS NOT NULL
  AND NULLIF(TRIM(s.occupation_title), '') IS NOT NULL
GROUP BY TRIM(s.occupation_id)
ON DUPLICATE KEY UPDATE
  occupation_title = VALUES(occupation_title),
  description = VALUES(description);

SELECT COUNT(*) AS occupations_loaded FROM occupations;

-- --------------------------------------------------------------------------
-- STEP 2. SKILLS from O*NET (distinct software names).
-- The O*NET category is an optional classification, not a Jobicy demand score.
-- --------------------------------------------------------------------------
INSERT INTO skills (skill_name, skill_category)
SELECT TRIM(s.skill_name),
       MIN(NULLIF(TRIM(s.skill_category), ''))
FROM stg_software_skills s
WHERE NULLIF(TRIM(s.skill_name), '') IS NOT NULL
GROUP BY TRIM(s.skill_name)
ON DUPLICATE KEY UPDATE
  skill_category = COALESCE(VALUES(skill_category), skill_category);

-- Additional observed skills extracted from actual Jobicy descriptions.
INSERT INTO skills (skill_name, skill_category)
SELECT DISTINCT TRIM(j.skill_name), NULL
FROM stg_job_skills j
WHERE NULLIF(TRIM(j.skill_name), '') IS NOT NULL
ON DUPLICATE KEY UPDATE
  skill_name = VALUES(skill_name);

SELECT COUNT(*) AS unique_skills_loaded FROM skills;

-- --------------------------------------------------------------------------
-- STEP 3. JOB_TITLES from O*NET; short_title is allowed to be NULL.
-- source_code is kept as text to preserve values such as '08'.
-- --------------------------------------------------------------------------
INSERT INTO job_titles (occupation_id, job_title, short_title, source_code)
SELECT TRIM(t.occupation_id),
       TRIM(t.job_title),
       MAX(NULLIF(TRIM(t.short_title), '')),
       COALESCE(NULLIF(TRIM(t.`source`), ''), 'UNKNOWN')
FROM stg_job_titles t
JOIN occupations o ON o.occupation_id = TRIM(t.occupation_id)
WHERE NULLIF(TRIM(t.job_title), '') IS NOT NULL
GROUP BY TRIM(t.occupation_id), TRIM(t.job_title),
         COALESCE(NULLIF(TRIM(t.`source`), ''), 'UNKNOWN')
ON DUPLICATE KEY UPDATE
  short_title = VALUES(short_title);

SELECT COUNT(*) AS alternative_titles_loaded FROM job_titles;

-- --------------------------------------------------------------------------
-- STEP 4. OCCUPATION_SKILLS (O*NET) with Y/N converted to 1/0.
-- --------------------------------------------------------------------------
INSERT INTO occupation_skills
  (occupation_id, skill_id, element_id, element_name, hot_technology, in_demand)
SELECT o.occupation_id,
       k.skill_id,
       TRIM(s.element_id),
       MAX(NULLIF(TRIM(s.skill_category), '')),
       MAX(CASE WHEN UPPER(TRIM(s.hot_technology)) = 'Y' THEN 1 ELSE 0 END),
       MAX(CASE WHEN UPPER(TRIM(s.in_demand)) = 'Y' THEN 1 ELSE 0 END)
FROM stg_software_skills s
JOIN occupations o ON o.occupation_id = TRIM(s.occupation_id)
JOIN skills k ON k.skill_name = TRIM(s.skill_name)
WHERE NULLIF(TRIM(s.element_id), '') IS NOT NULL
GROUP BY o.occupation_id, k.skill_id, TRIM(s.element_id)
ON DUPLICATE KEY UPDATE
  element_name = VALUES(element_name),
  hot_technology = VALUES(hot_technology),
  in_demand = VALUES(in_demand);

SELECT COUNT(*) AS occupation_skill_links_loaded FROM occupation_skills;

-- --------------------------------------------------------------------------
-- STEP 5. COMPANIES from Jobicy postings.
-- --------------------------------------------------------------------------
INSERT INTO companies (company_name)
SELECT DISTINCT TRIM(s.company_name)
FROM stg_jobicy_postings s
WHERE NULLIF(TRIM(s.company_name), '') IS NOT NULL
ON DUPLICATE KEY UPDATE
  company_name = VALUES(company_name);

SELECT COUNT(*) AS companies_loaded FROM companies;

-- --------------------------------------------------------------------------
-- STEP 6. JOB_POSTINGS from Jobicy. The CASE is preliminary title-based
-- classification (not guaranteed; manually inspect mismatches).
-- publication_date is imported as text; parse common ISO timestamp formats.
-- Dates are treated as UTC if your Python export wrote UTC timestamps.
-- Salary text becomes a number only when it is a plain number (e.g. 145000.0).
-- collected_at keeps the EARLIEST pull that saw a posting; last_seen_at the
-- LATEST, so re-loading after new pulls never loses the first-seen date.
-- --------------------------------------------------------------------------
INSERT INTO job_postings
  (job_id, job_title, company_id, occupation_id, role_category,
   job_geo, job_description, published_at,
   job_url, job_level, job_industry,
   salary_min, salary_max, salary_currency, salary_period,
   searched_role, collected_at, last_seen_at)
SELECT TRIM(j.job_id),
       TRIM(j.job_title),
       c.company_id,
       NULL,
       CASE
         WHEN LOWER(j.job_title) LIKE '%ai engineer%'
           OR LOWER(j.job_title) LIKE '%artificial intelligence engineer%'
           OR LOWER(j.job_title) LIKE '%machine learning engineer%'
           THEN 'AI Engineer'
         WHEN LOWER(j.job_title) LIKE '%data scientist%' THEN 'Data Scientist'
         WHEN LOWER(j.job_title) LIKE '%data engineer%' THEN 'Data Engineer'
         WHEN LOWER(j.job_title) LIKE '%data analyst%' THEN 'Data Analyst'
         WHEN LOWER(j.job_title) LIKE '%software engineer%'
           OR LOWER(j.job_title) LIKE '%software developer%'
           THEN 'Software Engineer'
         ELSE 'Other Tech'
       END,
       NULLIF(TRIM(j.location), ''),
       NULLIF(j.description_clean, ''),
       CASE
         WHEN TRIM(COALESCE(j.publication_date, ''))
              REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}'
         THEN STR_TO_DATE(
                REPLACE(LEFT(TRIM(j.publication_date), 19), 'T', ' '),
                '%Y-%m-%d %H:%i:%s'
              )
         ELSE NULL
       END,
       NULLIF(TRIM(j.job_url), ''),
       NULLIF(TRIM(j.job_level), ''),
       NULLIF(TRIM(j.job_industry), ''),
       CASE
         WHEN TRIM(COALESCE(j.salary_min, '')) REGEXP '^[0-9]+([.][0-9]+)?$'
         THEN CAST(TRIM(j.salary_min) AS DECIMAL(12,2))
         ELSE NULL
       END,
       CASE
         WHEN TRIM(COALESCE(j.salary_max, '')) REGEXP '^[0-9]+([.][0-9]+)?$'
         THEN CAST(TRIM(j.salary_max) AS DECIMAL(12,2))
         ELSE NULL
       END,
       NULLIF(UPPER(TRIM(j.salary_currency)), ''),
       NULLIF(LOWER(TRIM(j.salary_period)), ''),
       NULLIF(TRIM(j.searched_role), ''),
       COALESCE(CASE
         WHEN TRIM(COALESCE(j.collected_at, ''))
              REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}'
         THEN STR_TO_DATE(
                REPLACE(LEFT(TRIM(j.collected_at), 19), 'T', ' '),
                '%Y-%m-%d %H:%i:%s'
              )
         ELSE NULL
       END, CURRENT_TIMESTAMP),
       COALESCE(CASE
         WHEN TRIM(COALESCE(j.last_seen_at, ''))
              REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}'
         THEN STR_TO_DATE(
                REPLACE(LEFT(TRIM(j.last_seen_at), 19), 'T', ' '),
                '%Y-%m-%d %H:%i:%s'
              )
         ELSE NULL
       END, CURRENT_TIMESTAMP)
FROM stg_jobicy_postings j
LEFT JOIN companies c ON c.company_name = TRIM(j.company_name)
WHERE NULLIF(TRIM(j.job_id), '') IS NOT NULL
  AND NULLIF(TRIM(j.job_title), '') IS NOT NULL
ON DUPLICATE KEY UPDATE
  job_title = VALUES(job_title),
  company_id = VALUES(company_id),
  role_category = VALUES(role_category),
  job_geo = VALUES(job_geo),
  job_description = VALUES(job_description),
  published_at = VALUES(published_at),
  job_url = VALUES(job_url),
  job_level = VALUES(job_level),
  job_industry = VALUES(job_industry),
  salary_min = VALUES(salary_min),
  salary_max = VALUES(salary_max),
  salary_currency = VALUES(salary_currency),
  salary_period = VALUES(salary_period),
  searched_role = VALUES(searched_role),
  -- table name needed: the staging table also has these two column names
  collected_at = LEAST(job_postings.collected_at, VALUES(collected_at)),
  last_seen_at = GREATEST(job_postings.last_seen_at, VALUES(last_seen_at));

SELECT COUNT(*) AS unique_job_postings_loaded FROM job_postings;

-- --------------------------------------------------------------------------
-- STEP 7. OPTIONAL: Match EXACT unambiguous Jobicy titles to O*NET titles.
-- Senior/junior variants and titles matching multiple codes remain NULL.
-- Manually review unmatched titles before building user-facing comparisons.
-- --------------------------------------------------------------------------
SET @jobavenir_prior_safe_updates = @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;  -- only for this controlled mapping update

UPDATE job_postings jp
JOIN (
  SELECT LOWER(TRIM(a.job_title)) AS normalized_title,
         MIN(a.occupation_id) AS occupation_id
  FROM (
    SELECT jt.job_title, jt.occupation_id FROM job_titles jt
    UNION ALL
    SELECT o.occupation_title AS job_title, o.occupation_id FROM occupations o
  ) a
  GROUP BY LOWER(TRIM(a.job_title))
  HAVING COUNT(DISTINCT a.occupation_id) = 1
) exact_match
  ON LOWER(TRIM(jp.job_title)) = exact_match.normalized_title
SET jp.occupation_id = exact_match.occupation_id
WHERE jp.occupation_id IS NULL;

SET SQL_SAFE_UPDATES = @jobavenir_prior_safe_updates;

-- --------------------------------------------------------------------------
-- STEP 8. JOB_SKILLS: connect actual Jobicy postings to distinct skills.
-- --------------------------------------------------------------------------
INSERT INTO job_skills (job_id, skill_id, extraction_method)
SELECT DISTINCT p.job_id, k.skill_id, 'keyword_match'
FROM stg_job_skills s
JOIN job_postings p ON p.job_id = TRIM(s.job_id)
JOIN skills k ON k.skill_name = TRIM(s.skill_name)
WHERE NULLIF(TRIM(s.skill_name), '') IS NOT NULL
ON DUPLICATE KEY UPDATE
  extraction_method = VALUES(extraction_method);

SELECT COUNT(*) AS job_skill_links_loaded FROM job_skills;

-- --------------------------------------------------------------------------
-- STEP 9. LOADING SUMMARY AND VALIDATION QUERIES (save screenshots).
-- --------------------------------------------------------------------------
SELECT 'occupations' AS table_name, COUNT(*) AS row_count FROM occupations
UNION ALL SELECT 'skills', COUNT(*) FROM skills
UNION ALL SELECT 'job_titles', COUNT(*) FROM job_titles
UNION ALL SELECT 'occupation_skills', COUNT(*) FROM occupation_skills
UNION ALL SELECT 'companies', COUNT(*) FROM companies
UNION ALL SELECT 'job_postings', COUNT(*) FROM job_postings
UNION ALL SELECT 'job_skills', COUNT(*) FROM job_skills;

-- No duplicate occupation IDs expected (PK prevents duplicates).
SELECT occupation_id, COUNT(*) AS duplicates
FROM occupations
GROUP BY occupation_id
HAVING COUNT(*) > 1;

-- No duplicate job IDs expected (PK prevents duplicates).
SELECT job_id, COUNT(*) AS duplicates
FROM job_postings
GROUP BY job_id
HAVING COUNT(*) > 1;

-- Foreign-key orphan check (InnoDB prevents invalid inserts).
SELECT js.job_id, js.skill_id
FROM job_skills js
LEFT JOIN job_postings jp ON jp.job_id = js.job_id
LEFT JOIN skills s ON s.skill_id = js.skill_id
WHERE jp.job_id IS NULL OR s.skill_id IS NULL;

-- Missing expected source fields. Review; don't silently delete.
SELECT COUNT(*) AS jobs_missing_company
FROM job_postings WHERE company_id IS NULL;

-- Fields the dashboard needs: link to the original posting, salary and level.
SELECT COUNT(*) AS total_postings,
       SUM(job_url IS NOT NULL) AS with_job_url,
       SUM(salary_min IS NOT NULL) AS with_salary_range,
       SUM(job_level IS NOT NULL) AS with_job_level
FROM job_postings;

-- Titles not yet mapped to a standardized O*NET occupation.
SELECT job_id, job_title, role_category
FROM job_postings
WHERE occupation_id IS NULL
ORDER BY job_title LIMIT 30;

-- Roles not recognized by the starter rules.
SELECT job_title, role_category
FROM job_postings
WHERE role_category = 'Other Tech'
ORDER BY job_title LIMIT 30;

-- --------------------------------------------------------------------------
-- STEP 10. MARKET_SKILL_DEMAND VIEW
-- Denominator: ALL collected postings in that role (even if no skills found).
-- Numerator: DISTINCT postings with a recognized skill in their descriptions.
-- This is mention frequency in the Jobicy sample, NOT whole-US job demand.
-- ============================================================================
CREATE OR REPLACE VIEW market_skill_demand AS
SELECT p.role_category,
       s.skill_name,
       COUNT(DISTINCT p.job_id) AS postings_with_skill,
       rt.total_role_postings,
       ROUND(100.0 * COUNT(DISTINCT p.job_id) /
             NULLIF(rt.total_role_postings, 0), 2) AS demand_percentage
FROM job_postings p
JOIN job_skills js ON js.job_id = p.job_id
JOIN skills s ON s.skill_id = js.skill_id
JOIN (
    SELECT role_category, COUNT(*) AS total_role_postings
    FROM job_postings
    GROUP BY role_category
) rt ON rt.role_category = p.role_category
GROUP BY p.role_category, s.skill_id, s.skill_name, rt.total_role_postings;

-- ANALYTICAL QUERY 1: Top skills for Data Analysts in the observed sample
SELECT role_category, skill_name, postings_with_skill,
       total_role_postings, demand_percentage
FROM market_skill_demand
WHERE role_category = 'Data Analyst'
ORDER BY demand_percentage DESC, postings_with_skill DESC
LIMIT 15;

-- ANALYTICAL QUERY 2: Compare common requested skills in two roles
SELECT skill_name,
       MAX(CASE WHEN role_category = 'Data Analyst'
                THEN demand_percentage END) AS data_analyst_pct,
       MAX(CASE WHEN role_category = 'Data Scientist'
                THEN demand_percentage END) AS data_scientist_pct
FROM market_skill_demand
WHERE role_category IN ('Data Analyst', 'Data Scientist')
GROUP BY skill_name
HAVING data_analyst_pct IS NOT NULL OR data_scientist_pct IS NOT NULL
ORDER BY COALESCE(data_analyst_pct, 0) +
         COALESCE(data_scientist_pct, 0) DESC
LIMIT 20;

-- ANALYTICAL QUERY 3: Available postings per role and geo eligibility
SELECT role_category,
       COALESCE(job_geo, 'Not specified') AS geographic_eligibility,
       COUNT(*) AS job_count
FROM job_postings
GROUP BY role_category, COALESCE(job_geo, 'Not specified')
ORDER BY job_count DESC, role_category;

-- ANALYTICAL QUERY 4: O*NET in-demand software for Data Scientists
SELECT o.occupation_title, s.skill_name,
       os.hot_technology, os.in_demand
FROM occupations o
JOIN occupation_skills os ON os.occupation_id = o.occupation_id
JOIN skills s ON s.skill_id = os.skill_id
WHERE o.occupation_title = 'Data Scientists'
  AND os.in_demand = 1
ORDER BY s.skill_name
LIMIT 30;

-- ANALYTICAL QUERY 5: Postings whose job titles matched O*NET unambiguously
SELECT o.occupation_title, COUNT(*) AS matched_job_postings
FROM job_postings jp
JOIN occupations o ON o.occupation_id = jp.occupation_id
GROUP BY o.occupation_title
ORDER BY matched_job_postings DESC;

-- --------------------------------------------------------------------------
-- STEP 11. CRUD DEMONSTRATION (Create / Read / Update / Delete)
-- All CRUD actions use temporary DEMO records and finish with ROLLBACK.
-- Run this block once for screenshots; it does NOT change your real dataset.
-- The test company is inserted solely to support the demo job posting.
-- --------------------------------------------------------------------------
START TRANSACTION;

-- C: Create a test company and a test Data Analyst posting
INSERT INTO companies (company_name)
VALUES ('__JOBAVENIR_DEMO_COMPANY__');

INSERT INTO job_postings
  (job_id, job_title, company_id, role_category, job_geo,
   job_description, published_at)
SELECT '__JOBAVENIR_DEMO_JOB__', 'Data Analyst - Demo', company_id,
       'Data Analyst', 'USA', 'SQL and Python - DEMO RECORD', UTC_TIMESTAMP()
FROM companies
WHERE company_name = '__JOBAVENIR_DEMO_COMPANY__';

-- R: Read test job
SELECT job_id, job_title, job_geo, job_description
FROM job_postings
WHERE job_id = '__JOBAVENIR_DEMO_JOB__';

-- U: Update test job
UPDATE job_postings
SET job_title = 'Senior Data Analyst - Demo',
    job_description = 'SQL, Python and Tableau - UPDATED DEMO RECORD'
WHERE job_id = '__JOBAVENIR_DEMO_JOB__';

-- Read the AFTER-update state
SELECT job_id, job_title, job_description
FROM job_postings
WHERE job_id = '__JOBAVENIR_DEMO_JOB__';

-- D: Delete test job and then its test company (safe FK order)
DELETE FROM job_postings
WHERE job_id = '__JOBAVENIR_DEMO_JOB__';

DELETE FROM companies
WHERE company_name = '__JOBAVENIR_DEMO_COMPANY__';

-- Confirm test record is no longer present
SELECT COUNT(*) AS demo_jobs_remaining
FROM job_postings
WHERE job_id = '__JOBAVENIR_DEMO_JOB__';

ROLLBACK;

-- --------------------------------------------------------------------------
-- STEP 12. OPTIONAL INVALID-DATA DEMONSTRATIONS (RUN ONE AT A TIME)
-- These are intentionally commented because they are EXPECTED TO FAIL.
-- Uncomment only to capture error screenshots, then comment them again.
-- --------------------------------------------------------------------------
-- Invalid case A: duplicate PK (fails if the target job ID already exists)
-- INSERT INTO occupations(occupation_id, occupation_title)
-- SELECT occupation_id, 'Duplicate Test' FROM occupations LIMIT 1;
--
-- Invalid case B: invalid foreign key (nonexistent job reference)
-- INSERT INTO job_skills(job_id, skill_id)
-- SELECT '__NONEXISTENT_JOB_ID__', skill_id FROM skills LIMIT 1;

SELECT 'FINISHED: Review row counts, validation results and demo screenshots' AS status;
