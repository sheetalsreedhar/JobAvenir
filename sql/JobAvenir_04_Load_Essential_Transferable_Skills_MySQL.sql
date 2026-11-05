-- ============================================================================
-- JobAvenir - MySQL 8.0+
-- FILE 4: Move O*NET Essential/Transferable Skills from staging to core tables
-- Requires: script 01, script 03, and staging CSV imports completed.
-- IMPORTANT: Run SECTION A first. Proceed to SECTION B ONLY if all checks pass.
-- ============================================================================
USE jobavenir_db;

-- ============================================================================
-- SECTION A: PRE-LOAD VALIDATIONS (execute this first)
-- ============================================================================
-- Check that the occupations PARENT table is populated (not just stg_occupations).
SELECT 'occupations parent' AS table_name, COUNT(*) AS row_count FROM occupations
UNION ALL SELECT 'stg_essential_skills', COUNT(*) FROM stg_essential_skills
UNION ALL SELECT 'stg_transferable_skills', COUNT(*) FROM stg_transferable_skills
UNION ALL SELECT 'essential_skill_ratings', COUNT(*) FROM essential_skill_ratings
UNION ALL SELECT 'transferable_skill_ratings', COUNT(*) FROM transferable_skill_ratings;

-- BOTH counts below must be 0. If not, do not run INSERTs yet.
SELECT 'Essential - missing occupation reference' AS problem, COUNT(*) AS problem_rows
FROM stg_essential_skills s
LEFT JOIN occupations o ON TRIM(s.occupation_id) = o.occupation_id
WHERE o.occupation_id IS NULL
UNION ALL
SELECT 'Transferable - missing occupation reference', COUNT(*)
FROM stg_transferable_skills s
LEFT JOIN occupations o ON TRIM(s.occupation_id) = o.occupation_id
WHERE o.occupation_id IS NULL;

-- BOTH counts below must be 0 (composite key is occupation+element+scale).
SELECT 'Essential - duplicated rating keys' AS problem,
       COALESCE(SUM(n - 1), 0) AS duplicate_excess_rows
FROM (
  SELECT COUNT(*) AS n FROM stg_essential_skills
  GROUP BY occupation_id, element_id, scale_id HAVING COUNT(*) > 1
) x
UNION ALL
SELECT 'Transferable - duplicated rating keys',
       COALESCE(SUM(n - 1), 0)
FROM (
  SELECT COUNT(*) AS n FROM stg_transferable_skills
  GROUP BY occupation_id, element_id, scale_id HAVING COUNT(*) > 1
) x;

-- Both should be 0. Mandatory key fields cannot be missing.
SELECT 'Essential - missing required key/name' AS problem, COUNT(*) AS problem_rows
FROM stg_essential_skills
WHERE NULLIF(TRIM(occupation_id), '') IS NULL
   OR NULLIF(TRIM(element_id), '') IS NULL
   OR NULLIF(TRIM(scale_id), '') IS NULL
   OR NULLIF(TRIM(skill_name), '') IS NULL
UNION ALL
SELECT 'Transferable - missing required key/name', COUNT(*)
FROM stg_transferable_skills
WHERE NULLIF(TRIM(occupation_id), '') IS NULL
   OR NULLIF(TRIM(element_id), '') IS NULL
   OR NULLIF(TRIM(scale_id), '') IS NULL
   OR NULLIF(TRIM(skill_name), '') IS NULL;

-- Check that numeric data fields have no nonnumeric strings other than blanks.
-- Should return 0 for each dataset; inspect any nonzero result.
SELECT 'Essential - malformed rating' AS problem, COUNT(*) AS problem_rows
FROM stg_essential_skills
WHERE NULLIF(TRIM(data_value), '') IS NOT NULL
  AND TRIM(data_value) NOT REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
UNION ALL
SELECT 'Transferable - malformed rating', COUNT(*)
FROM stg_transferable_skills
WHERE NULLIF(TRIM(data_value), '') IS NOT NULL
  AND TRIM(data_value) NOT REGEXP '^-?[0-9]+(\\.[0-9]+)?$';

-- Verify flags respect the Y/N constraints in the core tables.
SELECT 'Essential - invalid flags' AS problem, COUNT(*) AS problem_rows
FROM stg_essential_skills
WHERE (NULLIF(TRIM(recommend_suppress), '') IS NOT NULL
       AND UPPER(TRIM(recommend_suppress)) NOT IN ('Y','N'))
   OR (NULLIF(TRIM(not_relevant), '') IS NOT NULL
       AND UPPER(TRIM(not_relevant)) NOT IN ('Y','N'))
UNION ALL
SELECT 'Transferable - invalid flags', COUNT(*)
FROM stg_transferable_skills
WHERE (NULLIF(TRIM(recommend_suppress), '') IS NOT NULL
       AND UPPER(TRIM(recommend_suppress)) NOT IN ('Y','N'))
   OR (NULLIF(TRIM(not_relevant), '') IS NOT NULL
       AND UPPER(TRIM(not_relevant)) NOT IN ('Y','N'));

-- ============================================================================
-- SECTION B: INSERT (run ONLY after Section A checks pass)
-- Run once when both core tables are empty. Do not rerun if already populated.
-- Omit occupation_title: it is kept in occupations and available via JOIN.
-- ============================================================================
START TRANSACTION;

INSERT INTO essential_skill_ratings (
    occupation_id, element_id, skill_name, scale_id, scale_name,
    data_value, sample_size, standard_error, lower_ci_bound, upper_ci_bound,
    recommend_suppress, not_relevant, date_updated, domain_source
)
SELECT
    TRIM(occupation_id), TRIM(element_id), TRIM(skill_name),
    TRIM(scale_id), NULLIF(TRIM(scale_name), ''),
    CAST(NULLIF(TRIM(data_value), '') AS DECIMAL(5,2)),
    CAST(NULLIF(TRIM(sample_size), '') AS UNSIGNED),
    CAST(NULLIF(TRIM(standard_error), '') AS DECIMAL(7,4)),
    CAST(NULLIF(TRIM(lower_ci_bound), '') AS DECIMAL(7,4)),
    CAST(NULLIF(TRIM(upper_ci_bound), '') AS DECIMAL(7,4)),
    NULLIF(UPPER(TRIM(recommend_suppress)), ''),
    NULLIF(UPPER(TRIM(not_relevant)), ''),
    NULLIF(TRIM(date_updated), ''), NULLIF(TRIM(domain_source), '')
FROM stg_essential_skills;

INSERT INTO transferable_skill_ratings (
    occupation_id, element_id, skill_name, scale_id, scale_name,
    data_value, sample_size, standard_error, lower_ci_bound, upper_ci_bound,
    recommend_suppress, not_relevant, date_updated, domain_source
)
SELECT
    TRIM(occupation_id), TRIM(element_id), TRIM(skill_name),
    TRIM(scale_id), NULLIF(TRIM(scale_name), ''),
    CAST(NULLIF(TRIM(data_value), '') AS DECIMAL(5,2)),
    CAST(NULLIF(TRIM(sample_size), '') AS UNSIGNED),
    CAST(NULLIF(TRIM(standard_error), '') AS DECIMAL(7,4)),
    CAST(NULLIF(TRIM(lower_ci_bound), '') AS DECIMAL(7,4)),
    CAST(NULLIF(TRIM(upper_ci_bound), '') AS DECIMAL(7,4)),
    NULLIF(UPPER(TRIM(recommend_suppress)), ''),
    NULLIF(UPPER(TRIM(not_relevant)), ''),
    NULLIF(TRIM(date_updated), ''), NULLIF(TRIM(domain_source), '')
FROM stg_transferable_skills;

-- Review the MySQL Action Output: if any insert failed, run ROLLBACK
-- instead of the COMMIT below. Execute COMMIT only after BOTH inserts succeed.
COMMIT;

-- ============================================================================
-- SECTION C: VERIFY (should match staging counts)
-- ============================================================================
SELECT 'stg_essential_skills' AS table_name, COUNT(*) AS rows_loaded FROM stg_essential_skills
UNION ALL SELECT 'essential_skill_ratings', COUNT(*) FROM essential_skill_ratings
UNION ALL SELECT 'stg_transferable_skills', COUNT(*) FROM stg_transferable_skills
UNION ALL SELECT 'transferable_skill_ratings', COUNT(*) FROM transferable_skill_ratings;

SELECT o.occupation_title, e.skill_name, e.scale_name, e.data_value
FROM essential_skill_ratings e
JOIN occupations o ON e.occupation_id = o.occupation_id
WHERE o.occupation_title = 'Data Scientists'
LIMIT 15;

SELECT o.occupation_title, t.skill_name, t.scale_name, t.data_value
FROM transferable_skill_ratings t
JOIN occupations o ON t.occupation_id = o.occupation_id
WHERE o.occupation_title = 'Data Scientists'
LIMIT 15;
