JobAvenir – MySQL Workbench Setup and Milestone 2 Guide
======================================================

FILES
-----
1. JobAvenir_01_Create_Database_MySQL.sql
   Creates the jobavenir_db database: 7 staging tables (one per cleaned CSV)
   and 9 core tables, with all keys and constraints. Safe to run again on
   an existing database: it only adds tables that are missing.

2. JobAvenir_02_Load_and_Analyze_MySQL.sql
   Validates the staging data, loads the 9 core tables, runs validation
   queries, creates the market_skill_demand and occupation_skills VIEWs, and
   includes 8 analytical queries, a safe CRUD demo and optional invalid-data
   demos.

The earlier files 01b, 03 and 04 were merged into these two on 5 Nov 2026.

REQUIREMENTS
------------
- MySQL 8.0 or newer (MySQL Community Server, or MAMP 7+ with MySQL 8.0
  selected), with InnoDB support. MySQL 5.7 ignores the CHECK constraints.
- MySQL Workbench connected to that server. MAMP's MySQL listens on port
  8889 by default; standard MySQL on 3306.
- The cleaned O*NET + Jobicy CSV files in data/cleaned/.
- Do NOT use the old Snowflake SQL scripts in MySQL Workbench.

SCHEMA (16 tables + 2 views)
---------------------------
Staging (7): stg_occupations, stg_software_skills, stg_job_titles,
  stg_jobicy_postings, stg_job_skills, stg_essential_skills,
  stg_transferable_skills. Each matches one CSV, column for column.

Core (9):
  occupations                  O*NET occupations (PK occupation_id)
  skills                       ALL skills, one row each (PK skill_id)
                               skill_category = Technology / Essential /
                               Transferable; skill_source = O*NET / Jobicy;
                               onet_element_id for Essential/Transferable
  job_titles                   O*NET alternative titles (FK occupations)
  occupation_technology_skills Technology skills per occupation, with
                               technology_type, hot_technology, in_demand
                               (PK occupation_id + skill_id)
  occupation_skill_ratings     Essential + Transferable ratings per
                               occupation (PK occupation_id + skill_id +
                               scale_id; IM = Importance, LV = Level)
  companies                    Companies from Jobicy postings
  job_postings                 Jobicy postings (FK companies, occupations)
  job_skills                   Jobicy posting <-> skill links
  skill_aliases                Other names for a skill: a Jobicy keyword
                               (e.g. 'SQL') -> the O*NET skill it means
                               ('Structured query language SQL')
Views:
  market_skill_demand          Share of Jobicy postings per role that
                               mention each skill
  occupation_skills            One row per occupation x skill for EVERY
                               category: importance and skill_level for
                               Essential/Transferable, hot_technology /
                               in_demand / technology_type for Technology.
                               Reads the two link tables; stores nothing.

Why one skills table: a skill is one kind of thing whatever its type, so it
is stored once and labelled by skill_category. Jobicy postings and O*NET
occupations then point at the same skill_id. The two occupation link tables
stay separate because they hold different facts: a Technology skill is
"used" (with Hot Technology / In Demand flags), while an Essential or
Transferable skill is "rated" (Importance and Level, with statistics).
skill_aliases lets a Jobicy keyword and its O*NET name share one skill_id,
so posting mentions can be compared with O*NET's flags (query 8).

VERY IMPORTANT ORDER
--------------------
A. If jobavenir_db was built before the single skills table (scripts 01b,
   03 or 04), rebuild it once:
     DROP DATABASE jobavenir_db;
   (This only removes your local copy; everything is rebuilt from the CSVs.)
   A database built with the single skills table needs no DROP: running
   File 1 again adds skill_aliases, and File 2 moves any old Jobicy-only
   skills (SQL, AWS, Power BI, Java) onto their O*NET skills.
B. Open File 1 in MySQL Workbench and execute it.
C. Refresh the SCHEMAS panel. Look for jobavenir_db > Tables (16 tables).
D. Import the cleaned CSV files into the EXISTING staging tables.

   Recommended: run notebooks/importing_onet_data_into_MySql.ipynb. It
   imports all five O*NET CSVs
   in a few seconds, empties each staging table first when
   REPLACE_STAGING = 1, and checks every table's count against its CSV.
   Use it to repair a bad import too: just run it again.


   cleaned/occupations_clean.csv         -> jobavenir_db.stg_occupations
   cleaned/software_skills_clean.csv     -> jobavenir_db.stg_software_skills
   cleaned/job_titles_clean.csv          -> jobavenir_db.stg_job_titles
   cleaned/essential_skills_clean.csv    -> jobavenir_db.stg_essential_skills
   cleaned/transferable_skills_clean.csv -> jobavenir_db.stg_transferable_skills

   Alternative: right-click EACH existing stg_ table > Table Data Import
   Wizard. The wizard is slow on these files, and an import that is stopped
   or run twice leaves wrong row counts (TRUNCATE the table and import once).
   Select the matching CSV file > Use existing table > verify fields > import.
   Data is mapped by CSV columns; review all column names and order.
   All cleaned CSVs are plain UTF-8 without a BOM (byte-order mark). Saving
   a CSV with encoding="utf-8-sig" adds one, and the wizard then fails.
   Check UTF-8 encoding, comma separator, header row and quoted multiline
   job descriptions. MySQL Workbench import may be slow for large CSVs.

   The two Jobicy CSVs (jobicy_jobs_clean.csv and job_skills_clean.csv) are
   imported with notebooks/importing_jobicy_data_into_MySql.ipynb instead of
   the wizard, because the long descriptions break the wizard. After
   re-running the Jobicy notebook, keep REPLACE_STAGING = 1 so old staging
   rows are replaced rather than duplicated.

   Port: both import notebooks connect to 127.0.0.1 on port 3306. If your
   MySQL server uses another port (MAMP's default is 8889), create a file
   called .env in the project folder containing the line MYSQL_PORT=8889.
   .env is not committed to GitHub, so each teammate keeps their own port.
   Clear the notebooks' outputs before committing them, so no password is
   saved in the file.

E. Open File 2 and run Step 0 FIRST (counts of the 7 staging tables).
   Expected: 1,016 / 31,821 / 54,269 / 74 / 167 / 18,200 / 45,500 with the
   31 Oct 2026 Jobicy pull. The two Jobicy counts grow with every new pull.
F. Run loading Steps 1-9 in order. Each step that has a check prints it
   first; the check counts should all be 0.
G. Run the summary and validation SELECTs (Step 10), then the two views
   and the analytical queries (Step 11).
H. Run the CRUD demo block (Step 12) and capture before/after screenshots.
I. Leave the deliberately-failing test queries (Step 13) commented unless
   testing them.

EXPECTED RESULT (tested 5 Nov 2026 on MySQL 8.0.46, 31 Oct Jobicy pull)
-----------------------------------------------------------------------
  occupations                  1,016
  skills                       8,788  (Technology 8,753; Essential 10;
                                       Transferable 25; no Jobicy-only
                                       skills, thanks to the aliases)
  skill_aliases                    4
  job_titles                  54,269
  occupation_technology_skills 31,821
  occupation_skill_ratings    63,700  (Essential 18,200; Transferable 45,500)
  companies                       45
  job_postings                    74
  job_skills                     167
  market_skill_demand (view)      32 rows
  (companies, job_postings, job_skills and the view grow with new pulls)
  occupation_skills (view)    63,671 rows (Technology 31,821; Essential
                                       9,100; Transferable 22,750)
File 2 can be run again on the same staging data without duplicating rows.

CSV COLUMN HEADERS (EARLIER JUPYTER CLEANING CODE)
--------------------------------------------------
occupations_clean.csv:
 occupation_id, occupation_title, description

software_skills_clean.csv:
 occupation_id, occupation_title, skill_name, element_id, skill_category,
 hot_technology, in_demand
 (skill_category here is O*NET's technology type, e.g. 'Spreadsheet
 software'; File 2 stores it as occupation_technology_skills.technology_type)

job_titles_clean.csv:
 occupation_id, occupation_title, job_title, short_title, source

jobicy_jobs_clean.csv:
 job_id, job_title, company_name, location, description_clean,
 publication_date, job_url, job_level, job_industry, salary_min,
 salary_max, salary_currency, salary_period, searched_role,
 collected_at, last_seen_at

job_skills_clean.csv:
 job_id, skill_name

essential_skills_clean.csv and transferable_skills_clean.csv (15 columns):
 occupation_id, occupation_title, element_id, skill_name, scale_id,
 scale_name, data_value, sample_size, standard_error, lower_ci_bound,
 upper_ci_bound, recommend_suppress, not_relevant, date_updated,
 domain_source

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
- Essential = O*NET Basic Skills (element IDs 2.A.*); Transferable = O*NET
  Cross-Functional Skills (2.B.*). Each is rated on two scales, Importance
  (IM, 1-5) and Level (LV, 0-7). Keep the scales as separate rows; do not
  average them together. not_relevant is only filled for Level.
- Optional statistical fields (sample size, standard error, CI bounds)
  can remain NULL; do not delete whole rows just for optional missing values.
- date_updated is written '08/2026' in the essential CSV and 'Aug-26' in the
  transferable CSV; File 2 stores both as 'YYYY-MM'.
- technology_type belongs to the occupation link, not to the skill: 151 of
  the 8,753 O*NET tools are grouped under different types in different
  occupations.
- Jobicy keywords that match an O*NET technology name exactly (Python,
  Tableau, PostgreSQL, Snowflake, Docker, Microsoft Excel) reuse the O*NET
  skill row. The others are linked through skill_aliases: SQL -> Structured
  query language SQL, AWS -> Amazon Web Services AWS software, Power BI ->
  Microsoft Power BI, Java -> Oracle Java. When the skill dictionary in
  notebook 02 gains a keyword whose O*NET name differs, add a row to the
  alias list in File 2 Step 2d. A keyword with neither becomes a
  Jobicy-only skill (skill_source = 'Jobicy').
- Jobicy collection (notebook 02) has no role filter. Each pull makes one
  search for all U.S.-eligible jobs plus one search per Jobicy industry,
  following nextCursor pages. Jobicy asks for at most one pull per hour; the
  notebook refuses to start a pull within an hour of the last one.
- Every Jobicy pull is saved unchanged in data/jobicy/raw/<UTC time>/.
  The cleaning notebook reads only those saved files, never the live API,
  and combines all pulls, so the dataset grows with each pull.
- job_url must be shown with each posting: Jobicy asks API users to credit
  Jobicy and link to the original posting.
- Jobicy geo=usa describes remote jobs available to US applicants. It does
  not prove the employer's office is located in a given US state.
- The title classification of Data Analyst / Data Scientist / Data Engineer /
  Software Engineer / AI Engineer is based on simple title keywords. Other
  postings are 'Other Tech' when the title names a technical job (engineer,
  developer, programmer, DevOps, architect) or Jobicy files them under a
  tech industry, and 'Non-Tech' otherwise.
- An exact unambiguous O*NET title match is attempted; others remain NULL.
  Document and review the unmatched titles; do not force unreliable links.
- Skill demand is COUNT(DISTINCT postings mentioning skill) divided by the
  total collected postings for the role, even when some descriptions have no
  recognized skills. It measures a sample's skill mention frequency, not
  nationwide market demand. A mention is not necessarily a required skill.
- A view updates when underlying MySQL tables change, but fetching new API
  postings requires re-running your Python ingestion process separately.
- The SQL contains no secrets. Never commit database passwords to GitHub.

WHAT TO PUT IN YOUR MILESTONE 2 WORD REPORT
--------------------------------------------
1. Updated schema diagram of the 9 core tables; explain PK, FK, 1-to-many
   and many-to-many relationships, the single skills table with
   skill_category, and your normalization decisions.
2. Data integrity: MySQL InnoDB PK/FK enforcement and CHECK constraints;
   show duplicate-ID, invalid-FK and invalid-category tests; demonstrate
   Short Title handling.
3. Data loading: original sources, cleaning notebooks, staging tables,
   import procedure, loaded table counts and screenshots.
4. CRUD: show INSERT/SELECT/UPDATE/DELETE for demonstration posting, with
   actual screenshots and explanation. The demo uses a transaction/rollback.
5. Three or more analytical SQL queries with actual output + explanation.
6. Repository link + README for reproducing the database.
7. Individual contributions and AI-assistance disclosure, when applicable.

TROUBLESHOOTING
---------------
- If 'Table doesn't exist': run File 1 and execute USE jobavenir_db;
- If "Unknown column" for skill_category, technology_type or
  occupation_skill_ratings: the database was built with the old scripts.
  DROP DATABASE jobavenir_db; and rebuild from File 1.
- If column mismatch: check CSV headers against staging table definitions.
- If Import Wizard sees incorrect columns: ensure it skips header and uses
  the existing staging table, not a newly auto-generated table.
- If imported data are blank: inspect CSV encoding, delimiter and quoting.
- If the wizard says "'ascii' codec can't decode byte 0xef in position 0":
  the CSV starts with a UTF-8 BOM. Re-save it as plain UTF-8 (in Pandas,
  to_csv(..., encoding="utf-8")) and import again.
- If foreign key error 1452: load parent tables first and check unmatched IDs.
- If duplicate key error 1062: inspect source duplicates / re-imports.
- If check constraint error 3819: a value is outside its allowed list
  (skill_category, scale_id or a Y/N flag).
- If an import notebook says "Can't connect": check the port it prints
  ("Using MySQL port ...") matches your Workbench connection. Put
  MYSQL_PORT=<your port> in the project's .env file (MAMP 8889, standard
  MySQL 3306) and check that the server is running.
- If a staging count is wrong (e.g. stg_job_titles above 54,269): run
  notebooks/importing_onet_data_into_MySql.ipynb with REPLACE_STAGING = 1.
- If your SQL uses Snowflake-only keywords (ILIKE, QUALIFY, IFF): you're
  running the OLD script; use the MySQL files instead.
- If a previous CREATE TABLE used a different design, IF NOT EXISTS will
  not modify it. Inspect SHOW CREATE TABLE ... and reconcile deliberately.
- Workbench shows warning 1287 ("'VALUES function' is deprecated") on the
  load steps. It is only a notice; the loads work on MySQL 8.0.

Official MySQL Workbench import wizard documentation:
https://dev.mysql.com/doc/workbench/en/wb-admin-export-import-table.html

UPDATED REFERENCES
------------------
O*NET database and download information: https://www.onetcenter.org/database.html
MySQL database reference: https://dev.mysql.com/doc/

VERSION NOTE: Updated 5 November 2026 for the single skills table. The
expected counts above come from a fresh test build; record your own counts
and screenshots from your machine for the report.
