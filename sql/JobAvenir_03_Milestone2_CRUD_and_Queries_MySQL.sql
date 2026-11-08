-- ============================================================================
-- JOBAVENIR | ADT FINAL PROJECT MILESTONE 2
-- Application-oriented SQL queries, read-only validation, and safe CRUD demo
-- MySQL Community Server 8.x / MySQL Workbench
-- ============================================================================
-- This file is prepared from JobAvenir MySQL schema:
-- occupations(occupation_id, occupation_title),
-- skills(skill_id, skill_name),
-- job_postings(job_id, job_title, company_id, occupation_id, role_category,
--   job_geo, job_description, published_at),
-- job_skills(job_id, skill_id).
-- ============================================================================

USE jobavenir_db;

-- 0: SCHEMA INSPECTION: run before other sections
SELECT DATABASE() AS current_database;
SHOW TABLES;
DESCRIBE job_postings;
DESCRIBE job_skills;
DESCRIBE skills;
DESCRIBE occupations;
-- Your screenshot shows additional tables such as occupation_skill_ratings
-- and occupation_technologies. Their full names/columns should be verified
-- with SHOW TABLES and DESCRIBE before writing queries against them.

-- 0B: CHECK POPULATED FINAL TABLES
SELECT 'job_postings' AS table_name, COUNT(*) AS row_count FROM job_postings
UNION ALL SELECT 'job_skills', COUNT(*) FROM job_skills
UNION ALL SELECT 'skills', COUNT(*) FROM skills
UNION ALL SELECT 'occupations', COUNT(*) FROM occupations;

-- ============================================================================
-- APPLICATION QUERY 1: Market skill mention percentage by job role
-- The denominator includes all collected postings in each role category,
-- including those where no skill was detected. Percentages need not sum to 100.
-- ============================================================================
SELECT
    jp.role_category,
    s.skill_name,
    COUNT(DISTINCT jp.job_id) AS postings_mentioning_skill,
    totals.total_role_postings,
    ROUND(
        100.0 * COUNT(DISTINCT jp.job_id) /
        NULLIF(totals.total_role_postings, 0), 2
    ) AS demand_percentage
FROM job_postings AS jp
JOIN job_skills AS js ON js.job_id = jp.job_id
JOIN skills AS s ON s.skill_id = js.skill_id
JOIN (
    SELECT role_category, COUNT(*) AS total_role_postings
    FROM job_postings
    GROUP BY role_category
) AS totals ON totals.role_category = jp.role_category
GROUP BY jp.role_category, s.skill_id, s.skill_name, totals.total_role_postings
ORDER BY jp.role_category, demand_percentage DESC, s.skill_name;

-- ============================================================================
-- APPLICATION QUERY 2: Data Analyst versus Data Scientist skill comparison
-- Express each role's skill frequency as a percentage of that role's postings.
-- ============================================================================
SELECT
    s.skill_name,
    COUNT(DISTINCT CASE
        WHEN jp.role_category = 'Data Analyst' THEN jp.job_id
    END) AS data_analyst_postings,
    ROUND(
        100.0 * COUNT(DISTINCT CASE
            WHEN jp.role_category = 'Data Analyst' THEN jp.job_id
        END) / NULLIF((
            SELECT COUNT(*) FROM job_postings
            WHERE role_category = 'Data Analyst'
        ), 0), 2
    ) AS data_analyst_pct,
    COUNT(DISTINCT CASE
        WHEN jp.role_category = 'Data Scientist' THEN jp.job_id
    END) AS data_scientist_postings,
    ROUND(
        100.0 * COUNT(DISTINCT CASE
            WHEN jp.role_category = 'Data Scientist' THEN jp.job_id
        END) / NULLIF((
            SELECT COUNT(*) FROM job_postings
            WHERE role_category = 'Data Scientist'
        ), 0), 2
    ) AS data_scientist_pct
FROM job_postings AS jp
JOIN job_skills AS js ON js.job_id = jp.job_id
JOIN skills AS s ON s.skill_id = js.skill_id
WHERE jp.role_category IN ('Data Analyst', 'Data Scientist')
GROUP BY s.skill_id, s.skill_name
ORDER BY GREATEST(COALESCE(data_analyst_pct, 0),
                  COALESCE(data_scientist_pct, 0)) DESC, s.skill_name
LIMIT 25;

-- ============================================================================
-- APPLICATION QUERY 3: Count collected Jobicy jobs by role and geo
-- Jobicy geo often describes remote-worker eligibility, not office location.
-- This query powers the JobAvenir role/location summary.
-- ============================================================================
SELECT
    role_category,
    COALESCE(NULLIF(TRIM(job_geo), ''), 'Not specified') AS geographic_eligibility,
    COUNT(*) AS number_of_postings
FROM job_postings
GROUP BY role_category, COALESCE(NULLIF(TRIM(job_geo), ''), 'Not specified')
ORDER BY number_of_postings DESC, role_category;

-- ============================================================================
-- APPLICATION QUERY 4 (EXTRA): Companies and their Jobicy postings
-- Demonstrates a JOIN between employers and job records.
-- ============================================================================
SELECT
    c.company_name,
    COUNT(jp.job_id) AS collected_job_postings,
    COUNT(DISTINCT jp.role_category) AS distinct_role_categories
FROM companies AS c
JOIN job_postings AS jp ON jp.company_id = c.company_id
GROUP BY c.company_id, c.company_name
ORDER BY collected_job_postings DESC, c.company_name
LIMIT 20;

-- OPTIONAL O*NET SKILLS / USER SKILL GAP QUERY:
-- Your screenshot includes occupation_skill_ratings, occupation_technologies,
-- skill_aliases, app_users, user_skills. Inspect their actual field definitions
-- using DESCRIBE before adding joins; do not assume the older occupation_skills
-- table still exists. These queries can be added after schema confirmation.

-- ============================================================================
-- ============================================================================
-- INTEGRITY CHECKS (read-only; capture results)
-- ============================================================================
-- Expected: zero duplicates; PK already prevents duplicate job_id.
SELECT job_id, COUNT(*) AS duplicate_count
FROM job_postings
GROUP BY job_id
HAVING COUNT(*) > 1;

-- Expected: zero orphans; InnoDB FK should prevent them.
SELECT js.job_id, js.skill_id
FROM job_skills AS js
LEFT JOIN job_postings AS jp ON jp.job_id = js.job_id
LEFT JOIN skills AS s ON s.skill_id = js.skill_id
WHERE jp.job_id IS NULL OR s.skill_id IS NULL;

-- Jobicy title-to-O*NET matching is not always possible; NULL is allowed.
SELECT role_category, COUNT(*) AS jobs,
       SUM(occupation_id IS NULL) AS unmapped_occupation_ids
FROM job_postings
GROUP BY role_category;

-- ============================================================================
-- CRUD DEMO: safe, realistic application operation on a DEMO job posting.
-- IMPORTANT: Run this entire sequence in order in ONE connection/session.
-- It does NOT permanently change your real data; ROLLBACK undoes the INSERT.
-- Use screenshots after CREATE, READ, UPDATE, and DELETE, before ROLLBACK.
-- If the demo ID already exists, STOP; choose a new demo ID.
-- ============================================================================
SELECT COUNT(*) AS existing_demo_id
FROM job_postings
WHERE job_id = '__JOBAVENIR_MILESTONE2_DEMO_01__';

START TRANSACTION;

-- C: Add a hypothetical remote Data Analyst posting to JobAvenir.
INSERT INTO job_postings
    (job_id, job_title, role_category, job_geo, job_description, published_at)
VALUES
    ('__JOBAVENIR_MILESTONE2_DEMO_01__',
     'Junior Data Analyst (DEMO)',
     'Data Analyst',
     'USA',
     'Demo posting seeking SQL, Python, and Excel; not a real Jobicy listing.',
     UTC_TIMESTAMP());

-- R: Display the new posting (screenshot: created record).
SELECT job_id, job_title, role_category, job_geo, job_description
FROM job_postings
WHERE job_id = '__JOBAVENIR_MILESTONE2_DEMO_01__';

-- U: Update the posting to reflect a revised requirement (screenshot: after).
UPDATE job_postings
SET job_title = 'Data Analyst - SQL & Tableau (DEMO)',
    job_description = 'Updated demo requirements: SQL, Tableau, Python.'
WHERE job_id = '__JOBAVENIR_MILESTONE2_DEMO_01__';

SELECT job_id, job_title, role_category, job_geo, job_description
FROM job_postings
WHERE job_id = '__JOBAVENIR_MILESTONE2_DEMO_01__';

-- D: Remove the sample posting, as when a listing is withdrawn.
DELETE FROM job_postings
WHERE job_id = '__JOBAVENIR_MILESTONE2_DEMO_01__';

SELECT COUNT(*) AS demo_job_rows_after_delete
FROM job_postings
WHERE job_id = '__JOBAVENIR_MILESTONE2_DEMO_01__';

-- Roll back all demonstration changes as a safety precaution.
ROLLBACK;

-- Final confirmation: the example record does not remain in the database.
SELECT COUNT(*) AS demo_job_rows_final
FROM job_postings
WHERE job_id = '__JOBAVENIR_MILESTONE2_DEMO_01__';

-- NOTE: For reproducibility, include your original SQL setup/loading scripts,
--       data files or permitted source links, cleaning notebooks, and README.
--       Do NOT commit credentials. Document meaningful AI use and validation.
