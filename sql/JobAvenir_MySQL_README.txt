JobAvenir – MySQL Workbench Setup and Milestone 2 Guide
======================================================

FILES
-----
1. JobAvenir_01_Create_Database_MySQL.sql
   Creates MySQL database, 5 import/staging tables, and 7 normalized tables.

1b. JobAvenir_01b_Add_Jobicy_Fields_MySQL.sql
  Run ONCE on a database created before the Jobicy URL, salary, level,
  industry, and search-tag columns existed. Adds them to stg_jobicy_postings
  and job_postings.
   Skip it on a new database (File 1 already creates them).

2. JobAvenir_02_Load_and_Analyze_MySQL.sql
   Loads cleaned CSVs from staging into core, validates relationships, creates
   market_skill_demand VIEW, includes 5 analytical queries and safe CRUD demo.

3. JobAvenir_03_Add_Essential_Transferable_Skills_MySQL.sql
   Adds TWO staging tables and TWO final rating tables for newly downloaded
   O*NET Essential and Transferable Skills. Preserves all existing tables.

4. JobAvenir_04_Load_Essential_Transferable_Skills_MySQL.sql
   Checks staging data, validates occupation references and rating keys,
   inserts cleaned rows into final rating tables, and verifies totals and joins.
   WARNING: Section B insert results are not yet confirmed; run its validation
   checks first and review success before committing the transaction.

REQUIREMENTS
------------
- MySQL Community Server 8.0 or newer, with InnoDB support.
- MySQL Workbench connected to that server.
- Your actual cleaned O*NET + Jobicy CSV files generated in Jupyter Notebook.
- Do NOT use the old Snowflake SQL scripts in MySQL Workbench.

VERY IMPORTANT ORDER
--------------------
A. Open File 1 in MySQL Workbench and execute it once.
   Database already created with the earlier File 1? Also run File 1b once.
B. Refresh the SCHEMAS panel. Look for jobavenir_db > Tables.
C. Import the following cleaned CSV files into the EXISTING staging tables:

   cleaned/occupations_clean.csv     -> jobavenir_db.stg_occupations
   cleaned/software_skills_clean.csv -> jobavenir_db.stg_software_skills
   cleaned/job_titles_clean.csv      -> jobavenir_db.stg_job_titles
   cleaned/jobicy_jobs_clean.csv     -> jobavenir_db.stg_jobicy_postings
   cleaned/job_skills_clean.csv      -> jobavenir_db.stg_job_skills
   cleaned/essential_skills_clean.csv -> jobavenir_db.stg_essential_skills
   cleaned/transferable_skills_clean.csv -> jobavenir_db.stg_transferable_skills

   Right-click EACH existing stg_ table > Table Data Import Wizard.
   Select the matching CSV file > Use existing table > verify fields > import.
   Data is mapped by CSV columns; review all column names and order.
   Check UTF-8 encoding, comma separator, header row and quoted multiline
   job descriptions. The original Python Pandas to_csv() uses quoted fields
   as needed. MySQL Workbench import may be slow for large CSVs; monitor errors.

   The two Jobicy CSVs (jobicy_jobs_clean.csv and job_skills_clean.csv) are
   imported with notebooks/importing_jobicy_data_into_MySql.ipynb instead of
   the wizard, because the long descriptions break the wizard. After
   re-running the Jobicy notebook, keep REPLACE_STAGING = 1 so old staging
   rows are replaced rather than duplicated.

   If you haven't produced job_skills_clean.csv yet, finish your Python skill
   extraction; otherwise the job_skills table and market_skill_demand view
   will be empty even if the job_postings table contains records.

D. Open File 2 and run Step 0 FIRST (SELECTs that count staging rows).
   The O*NET original data sizes reported earlier were:
     occupations: 1,016; software skills: 31,821; job titles: 54,269.
   Actual cleaned counts can differ. Jobicy results will vary with API data.
E. After verifying the stage counts, run loading Steps 1–8 in order.
F. Run the validation SELECTs and Market Skill Demand view (Steps 9–10).
G. Run the CRUD demo block (Step 11) and capture before/after screenshots.
H. Leave the deliberately-failing test queries commented unless testing them.

NOVEMBER 5, 2026 - ESSENTIAL + TRANSFERABLE SKILLS SQL UPDATE
-------------------------------------------------------------
Purpose: Expand JobAvenir beyond O*NET Software Skills to include O*NET
Essential Skills and Transferable Skills as occupation-specific ratings.

WORK COMPLETED / VERIFIED IN MYSQL WORKBENCH:
- Opened and used script 03 to add the four new tables:
    stg_essential_skills      (15 CSV-compatible columns)
    stg_transferable_skills   (15 CSV-compatible columns)
    essential_skill_ratings  (14 normalized columns)
    transferable_skill_ratings (14 normalized columns)
- Loaded the cleaned O*NET CSVs into the existing staging tables:
    essential_skills_clean.csv    -> stg_essential_skills
    transferable_skills_clean.csv -> stg_transferable_skills
- Executed a UNION ALL count query to verify imported records.
  Confirmed by MySQL Workbench screenshot on November 5, 2026:
    stg_essential_skills       18,200 rows
    stg_transferable_skills    45,500 rows
    essential_skill_ratings        0 rows
    transferable_skill_ratings     0 rows
  Total staging rating records: 63,700.
- IMPORTANT: The screenshot shows the final rating tables were EMPTY at
  verification time. Do not say that all 63,700 records were transferred
  into the normalized tables until the final inserts are executed and
  new counts are checked.

DESIGN DECISIONS:
- Staging tables preserve all 15 cleaned CSV columns, including
  occupation_title; the final rating tables omit occupation_title because
  the title is already available from the occupations parent table.
- Ratings have composite primary keys: (occupation_id, element_id, scale_id).
  Two rating scales for the same occupation and skill are valid separate rows.
- occupation_id is a foreign key to occupations. Parent occupation rows
  MUST be in jobavenir_db.occupations before final rating rows are inserted.
- Optional statistical fields (sample size, standard error, CI bounds)
  can remain NULL; do not delete whole rows just for optional missing values.
- Preserve recommend_suppress and not_relevant as Y/N flags. Preserve
  scale_id and scale_name; do not mix importance and level ratings.

CSV COLUMN HEADERS FOR BOTH NEW CLEANED FILES (15 columns):
 occupation_id, occupation_title, element_id, skill_name, scale_id,
 scale_name, data_value, sample_size, standard_error, lower_ci_bound,
 upper_ci_bound, recommend_suppress, not_relevant, date_updated, domain_source

SQL USED TO VERIFY STAGING AND FINAL COUNTS:
 USE jobavenir_db;
 SELECT 'stg_essential_skills' AS table_name, COUNT(*) AS rows_loaded
   FROM stg_essential_skills
 UNION ALL
 SELECT 'stg_transferable_skills', COUNT(*)
   FROM stg_transferable_skills
 UNION ALL
 SELECT 'essential_skill_ratings', COUNT(*)
   FROM essential_skill_ratings
 UNION ALL
 SELECT 'transferable_skill_ratings', COUNT(*)
   FROM transferable_skill_ratings;

NEXT SQL STEPS - PREPARED, BUT NOT CONFIRMED COMPLETED:
 1. Check parent occupation table using:
      SELECT COUNT(*) FROM occupations;
 2. Open script 04 and run SECTION A: check invalid occupation IDs,
    duplicate (occupation_id, element_id, scale_id) keys, missing keys,
    malformed ratings and invalid Y/N flags. Fix any problems first.
 3. Run SECTION B only after checks pass and both final tables are empty:
    BEGIN/START TRANSACTION -> 2 INSERT INTO ... SELECT ... -> COMMIT.
    If either insert fails, ROLLBACK (do not commit partial data).
 4. Run SECTION C to verify the final counts match staging:
      essential_skill_ratings = 18,200 (if every record passes validation)
      transferable_skill_ratings = 45,500 (if every record passes validation)
    and test JOINs with occupations for 'Data Scientists'.
 5. Commit scripts 03 and 04, both cleaned CSVs, cleaning notebook, and
    this updated README to GitHub so the teammate can reproduce the work.
 6. Update the ERD and Milestone 2 report with 4 new tables and screenshots.

NOTE: Schema now has 7 original core + 5 original staging + 2 new core +
2 new staging = 16 total tables. Creating tables alone does not load data.

ORIGINAL FIVE CSV EXPECTED COLUMN HEADERS (EARLIER JUPYTER CLEANING CODE)
------------------------------------------------------------------
occupations_clean.csv:
 occupation_id, occupation_title, description

software_skills_clean.csv:
 occupation_id, occupation_title, skill_name, element_id, skill_category,
 hot_technology, in_demand

job_titles_clean.csv:
 occupation_id, occupation_title, job_title, short_title, source

jobicy_jobs_clean.csv:
 job_id, job_title, company_name, location, description_clean,
 publication_date, job_url, job_level, job_industry, salary_min,
 salary_max, salary_currency, salary_period, searched_role,
 collected_at, last_seen_at

job_skills_clean.csv:
 job_id, skill_name

If your Python-exported CSV has different headers, change the staging table
or the CSV before import. Do NOT silently mismatch columns.

IMPORTANT DATA NOTES
--------------------
- The 49,814 blanks previously observed in O*NET Short Title are acceptable.
  Those rows should not be discarded merely for missing short titles.
- O*NET SOC occupation codes must remain VARCHAR, not numeric.
- O*NET source codes, e.g. '08', must remain strings. If the original CSV was
  read into Pandas without dtype={'Source(s)':'string'}, recreate that CSV
  after reloading with the dtype to preserve leading zeros.
- Every Jobicy pull is saved unchanged in data/jobicy/raw/<UTC time>/.
  The cleaning notebook reads only those saved files, never the live API.
- job_url must be shown with each posting: Jobicy asks API users to credit
  Jobicy and link to the original posting.
- Jobicy geo=usa describes remote jobs available to US applicants. It does
  not prove the employer's office is located in a given US state.
- The title classification of Data Analyst / Data Scientist / Data Engineer /
  Software Engineer / AI Engineer is based on simple title keywords.
- An exact unambiguous O*NET title match is attempted; others remain NULL.
  Document and review the unmatched titles; do not force unreliable links.
- Skill demand is COUNT(DISTINCT postings mentioning skill) divided by the
  total collected postings for the role, even when some descriptions have no
  recognized skills. It measures a sample's skill mention frequency, not
  nationwide market demand. A mention is not necessarily a required skill.
- A view updates when underlying MySQL tables change, but fetching new API
  postings requires re-running your Python ingestion process separately.
- The code contains no secrets. Never commit database passwords to GitHub.

WHAT TO PUT IN YOUR MILESTONE 2 WORD REPORT
--------------------------------------------
1. Updated schema diagram of 9 core tables (7 original + 2 new skill-ratings tables); explain PK, FK, 1-to-many and
   many-to-many relationships and your normalization decisions.
2. Data integrity: MySQL InnoDB PK/FK enforcement; show duplicate-ID and
   invalid-FK tests; demonstrate Short Title handling.
3. Data loading: original sources, cleaning notebook, staging tables,
   import procedure, loaded table counts and screenshots.
4. CRUD: show INSERT/SELECT/UPDATE/DELETE for demonstration posting, with
   actual screenshots and explanation. The demo uses a transaction/rollback.
5. Three or more analytical SQL queries with actual output + explanation.
6. Repository link + README for reproducing the database.
7. Individual contributions and AI-assistance disclosure, when applicable.

TROUBLESHOOTING
---------------
- If 'Table doesn't exist': run File 1 and execute USE jobavenir_db;
- If column mismatch: check CSV headers against staging table definitions.
- If Import Wizard sees incorrect columns: ensure it skips header and uses
  the existing staging table, not a newly auto-generated table.
- If imported data are blank: inspect CSV encoding, delimiter and quoting.
- If foreign key error 1452: load parent tables first and check unmatched IDs.
- If duplicate key error 1062: inspect source duplicates / re-imports.
- If your SQL uses Snowflake-only keywords (ILIKE, QUALIFY, IFF): you're
  running the OLD script; use the MySQL files instead.
- If a previous CREATE TABLE used a different design, IF NOT EXISTS will
  not modify it. Inspect SHOW CREATE TABLE ... and reconcile deliberately.

Official MySQL Workbench import wizard documentation:
https://dev.mysql.com/doc/workbench/en/wb-admin-export-import-table.html

UPDATED REFERENCES
------------------
O*NET database and download information: https://www.onetcenter.org/database.html
MySQL database reference: https://dev.mysql.com/doc/

VERSION NOTE: Updated November 5, 2026. This is documentation of work
verified in screenshots and planned SQL steps, NOT a claim that all final
normalized tables are populated.
