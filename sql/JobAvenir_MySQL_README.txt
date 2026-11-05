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

CSV EXPECTED COLUMN HEADERS (MATCH THE EARLIER JUPYTER CLEANING CODE)
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
1. Schema diagram of the 7 related tables; explain PK, FK, 1-to-many and
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
