-- ============================================================================
-- JobAvenir | ADT Milestone 2 | FILE 2 OF 2
-- MySQL Community Server 8.0+ | Run in MySQL Workbench
-- PURPOSE: Verify staging CSVs, populate normalized tables, validate integrity,
--          create the market_skill_demand and occupation_skills VIEWs,
--          show analytical queries and CRUD.
-- ============================================================================
-- BEFORE RUNNING:
--   [ ] Ran JobAvenir_01_Create_Database_MySQL.sql successfully.
--   [ ] Imported all SEVEN cleaned CSV files into matching stg_* tables:
--       occupations_clean.csv         -> stg_occupations
--       software_skills_clean.csv     -> stg_software_skills
--       job_titles_clean.csv          -> stg_job_titles
--       jobicy_jobs_clean.csv         -> stg_jobicy_postings  (import notebook)
--       job_skills_clean.csv          -> stg_job_skills       (import notebook)
--       essential_skills_clean.csv    -> stg_essential_skills
--       transferable_skills_clean.csv -> stg_transferable_skills
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
-- Cleaned O*NET counts: 1016 occupations, 31821 software rows, 54269 titles,
-- 18200 essential and 45500 transferable rating rows.
-- Jobicy API counts vary. Zero Jobicy rows means no market results yet.
-- --------------------------------------------------------------------------
SELECT 'stg_occupations' AS table_name, COUNT(*) AS row_count
  FROM stg_occupations
UNION ALL SELECT 'stg_software_skills', COUNT(*) FROM stg_software_skills
UNION ALL SELECT 'stg_job_titles', COUNT(*) FROM stg_job_titles
UNION ALL SELECT 'stg_jobicy_postings', COUNT(*) FROM stg_jobicy_postings
UNION ALL SELECT 'stg_job_skills', COUNT(*) FROM stg_job_skills
UNION ALL SELECT 'stg_essential_skills', COUNT(*) FROM stg_essential_skills
UNION ALL SELECT 'stg_transferable_skills', COUNT(*) FROM stg_transferable_skills;

-- VALIDATION BEFORE LOADING: unmatched O*NET occupation codes (all 0 expected)
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
WHERE o.occupation_id IS NULL
UNION ALL
SELECT 'essential_skills', COUNT(*)
FROM stg_essential_skills e
LEFT JOIN stg_occupations o
  ON TRIM(e.occupation_id) = TRIM(o.occupation_id)
WHERE o.occupation_id IS NULL
UNION ALL
SELECT 'transferable_skills', COUNT(*)
FROM stg_transferable_skills t
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
-- STEP 2. SKILLS: one table for every skill, labelled by skill_category.
--   2a. Technology   : distinct O*NET software/technology names
--   2b. Essential    : O*NET Basic Skills, one row per element_id (2.A.*)
--   2c. Transferable : O*NET Cross-Functional Skills, one per element_id (2.B.*)
--   2d. Aliases      : Jobicy keywords whose O*NET name is different
--                      (e.g. 'SQL' -> 'Structured query language SQL')
--   2e. Technology   : Jobicy keywords that match no O*NET skill by exact
--                      name or alias get skill_source = 'Jobicy'. Exact
--                      matches such as 'Python' reuse the existing O*NET row.
-- --------------------------------------------------------------------------
-- Check first: an O*NET element listed in BOTH skill files (expected 0).
SELECT COUNT(*) AS elements_in_both_files
FROM (SELECT DISTINCT TRIM(element_id) AS element_id FROM stg_essential_skills) e
JOIN (SELECT DISTINCT TRIM(element_id) AS element_id FROM stg_transferable_skills) t
  ON t.element_id = e.element_id;

-- 2a. Technology skills from O*NET
INSERT INTO skills (skill_name, skill_category, skill_source)
SELECT DISTINCT TRIM(s.skill_name), 'Technology', 'O*NET'
FROM stg_software_skills s
WHERE NULLIF(TRIM(s.skill_name), '') IS NOT NULL
ON DUPLICATE KEY UPDATE
  skill_source = 'O*NET';

-- 2b. Essential skills
INSERT INTO skills (skill_name, skill_category, onet_element_id, skill_source)
SELECT MAX(TRIM(e.skill_name)), 'Essential', TRIM(e.element_id), 'O*NET'
FROM stg_essential_skills e
WHERE NULLIF(TRIM(e.element_id), '') IS NOT NULL
  AND NULLIF(TRIM(e.skill_name), '') IS NOT NULL
GROUP BY TRIM(e.element_id)
ON DUPLICATE KEY UPDATE
  skill_name = VALUES(skill_name);

-- 2c. Transferable skills
INSERT INTO skills (skill_name, skill_category, onet_element_id, skill_source)
SELECT MAX(TRIM(t.skill_name)), 'Transferable', TRIM(t.element_id), 'O*NET'
FROM stg_transferable_skills t
WHERE NULLIF(TRIM(t.element_id), '') IS NOT NULL
  AND NULLIF(TRIM(t.skill_name), '') IS NOT NULL
GROUP BY TRIM(t.element_id)
ON DUPLICATE KEY UPDATE
  skill_name = VALUES(skill_name);

-- 2d. Skill aliases: Jobicy keyword -> the O*NET Technology skill it means.
-- Add a row here when the Python skill dictionary gains a keyword whose
-- O*NET name is different. Keywords spelled exactly as in O*NET (Python,
-- Tableau, PostgreSQL, Snowflake, Docker, Microsoft Excel) need no alias.
INSERT INTO skill_aliases (alias_name, skill_id, alias_source)
SELECT a.alias_name, k.skill_id, 'Jobicy keyword'
FROM (
  SELECT 'SQL' AS alias_name, 'Structured query language SQL' AS onet_name
  UNION ALL SELECT 'AWS', 'Amazon Web Services AWS software'
  UNION ALL SELECT 'Power BI', 'Microsoft Power BI'
  UNION ALL SELECT 'Java', 'Oracle Java'
) a
JOIN skills k ON k.skill_name = a.onet_name
             AND k.skill_category = 'Technology'
ON DUPLICATE KEY UPDATE
  skill_id = VALUES(skill_id),
  alias_source = VALUES(alias_source);

SELECT a.alias_name, k.skill_name AS onet_skill_name
FROM skill_aliases a
JOIN skills k ON k.skill_id = a.skill_id
ORDER BY a.alias_name;

-- A keyword loaded earlier as a Jobicy-only skill (e.g. 'SQL' before the
-- aliases existed) is removed here, with its posting links; Step 9 links
-- those postings to the O*NET skill instead, so nothing is counted twice.
SET @jobavenir_prior_safe_updates = @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;  -- only for these two controlled clean-up deletes

DELETE js
FROM job_skills js
JOIN skills old_skill ON old_skill.skill_id = js.skill_id
JOIN skill_aliases a ON a.alias_name = old_skill.skill_name
WHERE old_skill.skill_source = 'Jobicy';

DELETE old_skill
FROM skills old_skill
JOIN skill_aliases a ON a.alias_name = old_skill.skill_name
WHERE old_skill.skill_source = 'Jobicy';

SET SQL_SAFE_UPDATES = @jobavenir_prior_safe_updates;

-- 2e. Jobicy keywords with no exact O*NET name and no alias become new
-- Technology skills (an existing row with the same name is left unchanged)
INSERT INTO skills (skill_name, skill_category, skill_source)
SELECT DISTINCT TRIM(j.skill_name), 'Technology', 'Jobicy'
FROM stg_job_skills j
LEFT JOIN skill_aliases a ON a.alias_name = TRIM(j.skill_name)
WHERE NULLIF(TRIM(j.skill_name), '') IS NOT NULL
  AND a.alias_name IS NULL
ON DUPLICATE KEY UPDATE
  skill_source = skills.skill_source;

SELECT skill_category, skill_source, COUNT(*) AS skills_loaded
FROM skills
GROUP BY skill_category, skill_source
ORDER BY skill_category, skill_source;

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
-- STEP 4. OCCUPATION_TECHNOLOGY_SKILLS (O*NET) with Y/N converted to 1/0.
-- technology_type keeps O*NET's grouping of the tool for this occupation.
-- --------------------------------------------------------------------------
-- Check first: a tool listed under two technology types in the SAME
-- occupation (expected 0; MAX() below would keep only one of them).
SELECT COUNT(*) AS occupation_tools_with_two_types
FROM (
  SELECT TRIM(occupation_id) AS occupation_id, TRIM(skill_name) AS skill_name
  FROM stg_software_skills
  GROUP BY TRIM(occupation_id), TRIM(skill_name)
  HAVING COUNT(DISTINCT TRIM(skill_category)) > 1
) x;

INSERT INTO occupation_technology_skills
  (occupation_id, skill_id, technology_type, hot_technology, in_demand)
SELECT o.occupation_id,
       k.skill_id,
       MAX(NULLIF(TRIM(s.skill_category), '')),
       MAX(CASE WHEN UPPER(TRIM(s.hot_technology)) = 'Y' THEN 1 ELSE 0 END),
       MAX(CASE WHEN UPPER(TRIM(s.in_demand)) = 'Y' THEN 1 ELSE 0 END)
FROM stg_software_skills s
JOIN occupations o ON o.occupation_id = TRIM(s.occupation_id)
JOIN skills k ON k.skill_name = TRIM(s.skill_name)
             AND k.skill_category = 'Technology'
GROUP BY o.occupation_id, k.skill_id
ON DUPLICATE KEY UPDATE
  technology_type = VALUES(technology_type),
  hot_technology = VALUES(hot_technology),
  in_demand = VALUES(in_demand);

SELECT COUNT(*) AS occupation_technology_links_loaded
FROM occupation_technology_skills;

-- --------------------------------------------------------------------------
-- STEP 5. OCCUPATION_SKILL_RATINGS: Essential and Transferable ratings in one
-- table. Skills are matched on O*NET element_id, so the skill name and
-- category are read from skills instead of being repeated in every row.
-- The two staging tables are read together; the table a row came from sets
-- its skill_category.
-- Check first: every count in the next two results should be 0.
-- --------------------------------------------------------------------------
WITH r AS (
  SELECT 'Essential' AS skill_category, e.* FROM stg_essential_skills e
  UNION ALL
  SELECT 'Transferable', t.* FROM stg_transferable_skills t
)
SELECT r.skill_category,
       COUNT(*) AS staged_rows,
       SUM(o.occupation_id IS NULL) AS missing_occupation,
       SUM(NULLIF(TRIM(r.element_id), '') IS NULL
           OR NULLIF(TRIM(r.scale_id), '') IS NULL
           OR NULLIF(TRIM(r.skill_name), '') IS NULL) AS missing_key_fields,
       SUM(NULLIF(TRIM(r.data_value), '') IS NOT NULL
           AND TRIM(r.data_value) NOT REGEXP '^-?[0-9]+(\\.[0-9]+)?$')
         AS malformed_rating,
       SUM(UPPER(TRIM(r.scale_id)) NOT IN ('IM', 'LV')) AS invalid_scale,
       SUM((NULLIF(TRIM(r.recommend_suppress), '') IS NOT NULL
            AND UPPER(TRIM(r.recommend_suppress)) NOT IN ('Y', 'N'))
           OR (NULLIF(TRIM(r.not_relevant), '') IS NOT NULL
            AND UPPER(TRIM(r.not_relevant)) NOT IN ('Y', 'N')))
         AS invalid_flags,
       SUM(NULLIF(TRIM(r.date_updated), '') IS NOT NULL
           AND TRIM(r.date_updated) NOT REGEXP '^[0-9]{1,2}/[0-9]{4}$'
           AND TRIM(r.date_updated) NOT REGEXP '^[A-Za-z]{3}-[0-9]{2}$')
         AS unreadable_date
FROM r
LEFT JOIN occupations o ON o.occupation_id = TRIM(r.occupation_id)
GROUP BY r.skill_category;

-- Duplicate rating keys (occupation + element + scale), expected 0
WITH r AS (
  SELECT 'Essential' AS skill_category, e.* FROM stg_essential_skills e
  UNION ALL
  SELECT 'Transferable', t.* FROM stg_transferable_skills t
)
SELECT COALESCE(SUM(n - 1), 0) AS duplicate_rating_rows
FROM (
  SELECT COUNT(*) AS n
  FROM r
  GROUP BY TRIM(r.occupation_id), TRIM(r.element_id), TRIM(r.scale_id)
  HAVING COUNT(*) > 1
) d;

-- date_updated arrives as '08/2026' (essential file) or 'Aug-26'
-- (transferable file); both are stored as 'YYYY-MM'.
INSERT INTO occupation_skill_ratings
  (occupation_id, skill_id, scale_id, data_value, sample_size,
   standard_error, lower_ci_bound, upper_ci_bound,
   recommend_suppress, not_relevant, date_updated, domain_source)
SELECT o.occupation_id,
       k.skill_id,
       UPPER(TRIM(r.scale_id)),
       CAST(NULLIF(TRIM(r.data_value), '') AS DECIMAL(5,2)),
       CAST(NULLIF(TRIM(r.sample_size), '') AS UNSIGNED),
       CAST(NULLIF(TRIM(r.standard_error), '') AS DECIMAL(7,4)),
       CAST(NULLIF(TRIM(r.lower_ci_bound), '') AS DECIMAL(7,4)),
       CAST(NULLIF(TRIM(r.upper_ci_bound), '') AS DECIMAL(7,4)),
       NULLIF(UPPER(TRIM(r.recommend_suppress)), ''),
       NULLIF(UPPER(TRIM(r.not_relevant)), ''),
       CASE
         WHEN TRIM(r.date_updated) REGEXP '^[0-9]{1,2}/[0-9]{4}$'
         THEN DATE_FORMAT(STR_TO_DATE(CONCAT('01/', TRIM(r.date_updated)),
                                      '%d/%m/%Y'), '%Y-%m')
         WHEN TRIM(r.date_updated) REGEXP '^[A-Za-z]{3}-[0-9]{2}$'
         THEN DATE_FORMAT(STR_TO_DATE(CONCAT('01-', TRIM(r.date_updated)),
                                      '%d-%b-%y'), '%Y-%m')
         ELSE NULL
       END,
       NULLIF(TRIM(r.domain_source), '')
FROM (
  SELECT 'Essential' AS skill_category, e.* FROM stg_essential_skills e
  UNION ALL
  SELECT 'Transferable', t.* FROM stg_transferable_skills t
) r
JOIN occupations o ON o.occupation_id = TRIM(r.occupation_id)
JOIN skills k ON k.onet_element_id = TRIM(r.element_id)
             AND k.skill_category = r.skill_category
ON DUPLICATE KEY UPDATE
  data_value = VALUES(data_value),
  sample_size = VALUES(sample_size),
  standard_error = VALUES(standard_error),
  lower_ci_bound = VALUES(lower_ci_bound),
  upper_ci_bound = VALUES(upper_ci_bound),
  recommend_suppress = VALUES(recommend_suppress),
  not_relevant = VALUES(not_relevant),
  date_updated = VALUES(date_updated),
  domain_source = VALUES(domain_source);

-- Staged vs loaded: the two columns should match for each category
SELECT 'Essential' AS skill_category,
       (SELECT COUNT(*) FROM stg_essential_skills) AS staged_rows,
       (SELECT COUNT(*) FROM occupation_skill_ratings r
          JOIN skills k ON k.skill_id = r.skill_id
         WHERE k.skill_category = 'Essential') AS loaded_rows
UNION ALL
SELECT 'Transferable',
       (SELECT COUNT(*) FROM stg_transferable_skills),
       (SELECT COUNT(*) FROM occupation_skill_ratings r
          JOIN skills k ON k.skill_id = r.skill_id
         WHERE k.skill_category = 'Transferable');

-- --------------------------------------------------------------------------
-- STEP 6. COMPANIES from Jobicy postings.
-- --------------------------------------------------------------------------
INSERT INTO companies (company_name)
SELECT DISTINCT TRIM(s.company_name)
FROM stg_jobicy_postings s
WHERE NULLIF(TRIM(s.company_name), '') IS NOT NULL
ON DUPLICATE KEY UPDATE
  company_name = VALUES(company_name);

SELECT COUNT(*) AS companies_loaded FROM companies;

-- --------------------------------------------------------------------------
-- STEP 7. JOB_POSTINGS from Jobicy. The CASE is preliminary title-based
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
         -- Titles the rules above miss: tech if the title names a technical
         -- job or Jobicy files the posting under a tech industry, otherwise
         -- Non-Tech (collection has no role filter, so sales, HR,
         -- marketing... postings arrive too)
         WHEN LOWER(j.job_title) REGEXP
              'engineer|developer|programmer|devops|architect'
           OR LOWER(COALESCE(j.job_industry, '')) REGEXP
              'software engineering|data science|cybersecurity|devops|technical support'
           THEN 'Other Tech'
         ELSE 'Non-Tech'
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
-- STEP 8. OPTIONAL: Match EXACT unambiguous Jobicy titles to O*NET titles.
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
-- STEP 9. JOB_SKILLS: connect actual Jobicy postings to distinct skills.
-- A keyword is matched through skill_aliases first (e.g. 'SQL' -> 'Structured
-- query language SQL'), otherwise by exact Technology skill name.
-- --------------------------------------------------------------------------
INSERT INTO job_skills (job_id, skill_id, extraction_method)
SELECT DISTINCT p.job_id, COALESCE(a.skill_id, k.skill_id), 'keyword_match'
FROM stg_job_skills s
JOIN job_postings p ON p.job_id = TRIM(s.job_id)
LEFT JOIN skill_aliases a ON a.alias_name = TRIM(s.skill_name)
LEFT JOIN skills k ON k.skill_name = TRIM(s.skill_name)
                  AND k.skill_category = 'Technology'
WHERE NULLIF(TRIM(s.skill_name), '') IS NOT NULL
  AND COALESCE(a.skill_id, k.skill_id) IS NOT NULL
ON DUPLICATE KEY UPDATE
  extraction_method = VALUES(extraction_method);

-- How each Jobicy keyword was matched (alias, exact O*NET name, or a new
-- Jobicy-only skill). 'Not linked' should not appear.
SELECT TRIM(s.skill_name) AS jobicy_keyword,
       COALESCE(ka.skill_name, k.skill_name) AS linked_skill,
       CASE
         WHEN a.alias_name IS NOT NULL THEN 'Alias'
         WHEN k.skill_source = 'O*NET' THEN 'Exact O*NET name'
         WHEN k.skill_source = 'Jobicy' THEN 'Jobicy-only skill'
         ELSE 'Not linked'
       END AS matched_by,
       COUNT(DISTINCT TRIM(s.job_id)) AS postings
FROM stg_job_skills s
LEFT JOIN skill_aliases a ON a.alias_name = TRIM(s.skill_name)
LEFT JOIN skills ka ON ka.skill_id = a.skill_id
LEFT JOIN skills k ON k.skill_name = TRIM(s.skill_name)
                  AND k.skill_category = 'Technology'
WHERE NULLIF(TRIM(s.skill_name), '') IS NOT NULL
GROUP BY TRIM(s.skill_name), COALESCE(ka.skill_name, k.skill_name), matched_by
ORDER BY postings DESC;

SELECT COUNT(*) AS job_skill_links_loaded FROM job_skills;

-- --------------------------------------------------------------------------
-- STEP 10. LOADING SUMMARY AND VALIDATION QUERIES (save screenshots).
-- --------------------------------------------------------------------------
SELECT 'occupations' AS table_name, COUNT(*) AS row_count FROM occupations
UNION ALL SELECT 'skills', COUNT(*) FROM skills
UNION ALL SELECT 'job_titles', COUNT(*) FROM job_titles
UNION ALL SELECT 'occupation_technology_skills', COUNT(*)
            FROM occupation_technology_skills
UNION ALL SELECT 'occupation_skill_ratings', COUNT(*)
            FROM occupation_skill_ratings
UNION ALL SELECT 'companies', COUNT(*) FROM companies
UNION ALL SELECT 'job_postings', COUNT(*) FROM job_postings
UNION ALL SELECT 'job_skills', COUNT(*) FROM job_skills
UNION ALL SELECT 'skill_aliases', COUNT(*) FROM skill_aliases;

-- Postings per role category (Non-Tech = outside the tech industries)
SELECT role_category, COUNT(*) AS postings
FROM job_postings
GROUP BY role_category
ORDER BY postings DESC;

-- Ratings per category and scale (each category: IM and LV counts are equal)
SELECT k.skill_category, r.scale_id, COUNT(*) AS ratings,
       COUNT(DISTINCT r.occupation_id) AS occupations,
       COUNT(DISTINCT r.skill_id) AS skills
FROM occupation_skill_ratings r
JOIN skills k ON k.skill_id = r.skill_id
GROUP BY k.skill_category, r.scale_id
ORDER BY k.skill_category, r.scale_id;

-- Each link table should only point to the right kind of skill (both 0).
-- A foreign key cannot check this, so it is checked here.
SELECT 'technology links to non-Technology skills' AS check_name,
       COUNT(*) AS problem_rows
FROM occupation_technology_skills ots
JOIN skills k ON k.skill_id = ots.skill_id
WHERE k.skill_category <> 'Technology'
UNION ALL
SELECT 'ratings for Technology skills', COUNT(*)
FROM occupation_skill_ratings r
JOIN skills k ON k.skill_id = r.skill_id
WHERE k.skill_category = 'Technology';

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
-- STEP 11. VIEWS (market_skill_demand, occupation_skills) AND ANALYTICS
--
-- MARKET_SKILL_DEMAND VIEW
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

-- OCCUPATION_SKILLS VIEW: one row per occupation x skill, for every skill
-- category. It reads the two link tables, so nothing is stored twice.
--   Technology rows   : hot_technology, in_demand and technology_type are
--                       filled; importance and skill_level are NULL because
--                       O*NET does not rate technology skills.
--   Essential and Transferable rows : importance (IM scale, 1-5) and
--                       skill_level (LV scale, 0-7) are filled; the
--                       technology columns are NULL.
CREATE OR REPLACE VIEW occupation_skills AS
SELECT ots.occupation_id,
       o.occupation_title,
       s.skill_id,
       s.skill_name,
       s.skill_category,
       CAST(NULL AS DECIMAL(5,2)) AS importance,
       CAST(NULL AS DECIMAL(5,2)) AS skill_level,
       ots.hot_technology,
       ots.in_demand,
       ots.technology_type
FROM occupation_technology_skills ots
JOIN occupations o ON o.occupation_id = ots.occupation_id
JOIN skills s ON s.skill_id = ots.skill_id
UNION ALL
SELECT r.occupation_id,
       o.occupation_title,
       s.skill_id,
       s.skill_name,
       s.skill_category,
       MAX(CASE WHEN r.scale_id = 'IM' THEN r.data_value END),
       MAX(CASE WHEN r.scale_id = 'LV' THEN r.data_value END),
       NULL,
       NULL,
       NULL
FROM occupation_skill_ratings r
JOIN occupations o ON o.occupation_id = r.occupation_id
JOIN skills s ON s.skill_id = r.skill_id
GROUP BY r.occupation_id, o.occupation_title,
         s.skill_id, s.skill_name, s.skill_category;

-- Rows in occupation_skills per category
-- (expected: Technology 31,821; Essential 9,100; Transferable 22,750)
SELECT skill_category, COUNT(*) AS occupation_skill_pairs
FROM occupation_skills
GROUP BY skill_category
ORDER BY skill_category;

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
JOIN occupation_technology_skills os ON os.occupation_id = o.occupation_id
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

-- ANALYTICAL QUERY 6: Most important Essential and Transferable skills for
-- Data Scientists, read from the one skills table (Importance 1-5, Level 0-7)
SELECT k.skill_category, k.skill_name,
       imp.data_value AS importance_1_to_5,
       lvl.data_value AS level_0_to_7
FROM occupations o
JOIN occupation_skill_ratings imp
  ON imp.occupation_id = o.occupation_id AND imp.scale_id = 'IM'
JOIN skills k ON k.skill_id = imp.skill_id
LEFT JOIN occupation_skill_ratings lvl
  ON lvl.occupation_id = imp.occupation_id
 AND lvl.skill_id = imp.skill_id
 AND lvl.scale_id = 'LV'
WHERE o.occupation_title = 'Data Scientists'
ORDER BY imp.data_value DESC, k.skill_name
LIMIT 15;

-- ANALYTICAL QUERY 7: Every skill linked to Data Scientists, by category,
-- read through the occupation_skills view
SELECT skill_category,
       COUNT(*) AS skills_linked,
       ROUND(AVG(importance), 2) AS avg_importance_1_to_5,
       SUM(in_demand = 1) AS in_demand_technologies
FROM occupation_skills
WHERE occupation_title = 'Data Scientists'
GROUP BY skill_category
ORDER BY skill_category;

-- ANALYTICAL QUERY 8: How often postings mention each skill, next to how
-- many O*NET occupations flag it as Hot Technology / In Demand. The skill
-- aliases make this join possible (e.g. Jobicy 'SQL' = O*NET 'Structured
-- query language SQL').
SELECT k.skill_name,
       COUNT(DISTINCT js.job_id) AS postings_mentioning,
       ROUND(100.0 * COUNT(DISTINCT js.job_id) /
             (SELECT COUNT(*) FROM job_postings), 1) AS pct_of_all_postings,
       (SELECT COUNT(*) FROM occupation_technology_skills t
         WHERE t.skill_id = k.skill_id AND t.hot_technology = 1)
         AS occupations_hot_technology,
       (SELECT COUNT(*) FROM occupation_technology_skills t
         WHERE t.skill_id = k.skill_id AND t.in_demand = 1)
         AS occupations_in_demand
FROM job_skills js
JOIN skills k ON k.skill_id = js.skill_id
GROUP BY k.skill_id, k.skill_name
ORDER BY postings_mentioning DESC;

-- --------------------------------------------------------------------------
-- STEP 12. CRUD DEMONSTRATION (Create / Read / Update / Delete)
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
-- STEP 13. OPTIONAL INVALID-DATA DEMONSTRATIONS (RUN ONE AT A TIME)
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
--
-- Invalid case C: skill_category outside the allowed list (CHECK constraint)
-- INSERT INTO skills (skill_name, skill_category) VALUES ('Demo Skill', 'Other');

SELECT 'FINISHED: Review row counts, validation results and demo screenshots' AS status;
