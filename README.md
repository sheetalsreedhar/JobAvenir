# JobAvenir
US Tech Job Market Analysis

> **Advanced Database Technologies (ADT) course project**  
> **Team:** Sheetal Sreedhar and Mounika Kage  
> **Last updated:** November 5, 2026

## Project overview

JobAvenir analyzes technology-related jobs and skills to support career exploration and skill-gap analysis. It combines standardized occupation and skill information from **O*NET** with recent remote job-posting data from the **Jobicy Jobs API**. Python and Pandas handle data collection and cleaning; **MySQL Community Server / MySQL Workbench** store and analyze the data. A **Streamlit dashboard is planned**, not yet part of the verified database milestone.

The team switched from Greenhouse to Jobicy for simpler public role-based searches, and from Snowflake to MySQL for local, no-cost development. Jobicy results represent the *collected sample of recent remote jobs eligible for U.S. applicants*, not the entire U.S. job market.

## Data sources

| Source | Dataset / derived file | Prepared rows | Purpose |
|---|---|---:|---|
| O*NET | `occupations_clean.csv` | 1,016 | Standardized occupations and descriptions |
| O*NET | `software_skills_clean.csv` | 31,821 | Occupation–software associations |
| O*NET | `job_titles_clean.csv` | 54,269 | Alternative occupation titles |
| Jobicy API | `jobicy_jobs_clean.csv` | 74 | Saved sample of job postings and descriptions |
| Derived from Jobicy | `job_skills_clean.csv` | 167 | Extracted job–skill pairs |
| O*NET | `essential_skills_clean.csv` | 18,200 | Occupation-specific essential-skill ratings |
| O*NET | `transferable_skills_clean.csv` | 45,500 | Occupation-specific transferable-skill ratings |

Row counts for the original five files were recorded during preparation. **The new Essential and Transferable staging imports were independently verified in MySQL Workbench on November 5, 2026.** Jobicy data is a saved snapshot and changes when the API is queried again.

## Processing completed before November 5

- Explored the original O*NET Occupation Data, Software Skills, and Job Titles datasets in Jupyter Notebook: column names, row counts, missing values, and duplicates.
- Renamed columns for SQL (for example, `O*NET-SOC Code` → `occupation_id`) and preserved O*NET codes as text.
- Kept valid Job Titles rows with missing optional `Short Title` values (49,814 missing in the source inspection).
- Retrieved Jobicy postings using API filters, including `geo=usa` and role-based `tag` searches; cleaned HTML descriptions and deduplicated posting IDs.
- Built a preliminary keyword-based technical skill extractor and exported `job_skills_clean.csv`. Skill mentions are **not** proof that a skill is required.
- Created `jobavenir_db` in MySQL with **5 staging tables and 7 relational tables** using `sql/JobAvenir_01_Create_Database_MySQL.sql`.
- Prepared `sql/JobAvenir_02_Load_and_Analyze_MySQL.sql` for normalized loading, relationship checks, CRUD examples, and job-skill-demand queries. Actual execution of all those steps must be verified separately.

## November 5, 2026 — Essential and Transferable Skills update

### 1. Cleaned the two new O*NET datasets

Cleaned both CSVs in Python/Pandas using the same 15-column mapping:

| Original O*NET column | Cleaned column |
|---|---|
| O*NET-SOC Code | `occupation_id` |
| Title | `occupation_title` |
| Element ID | `element_id` |
| Element Name | `skill_name` |
| Scale ID | `scale_id` |
| Scale Name | `scale_name` |
| Data Value | `data_value` |
| N | `sample_size` |
| Standard Error | `standard_error` |
| Lower CI Bound | `lower_ci_bound` |
| Upper CI Bound | `upper_ci_bound` |
| Recommend Suppress | `recommend_suppress` |
| Not Relevant | `not_relevant` |
| Date | `date_updated` |
| Domain Source | `domain_source` |

Processing included trimming text, retaining missing optional statistical fields, converting numeric rating fields, standardizing Y/N flags, examining duplicate rating keys, and checking occupation IDs against O*NET occupations. The identity of a rating is **(`occupation_id`, `element_id`, `scale_id`)**; different rating scales for the same occupation/skill are valid separate records. Preserve `scale_id` rather than averaging scales together.

### 2. Staged in MySQL

The two cleaned CSVs were first loaded with separate scripts (03 and 04), and the staging imports were verified in MySQL Workbench on November 5: `stg_essential_skills` = **18,200** rows and `stg_transferable_skills` = **45,500** rows. Later the same day the skills tables were consolidated (next section), and scripts 03 and 04 were merged into Files 1 and 2.

## November 5, 2026 — One skills table

All skills now live in **one `skills` table** with a `skill_category` field, instead of a separate table for each type of skill. Scripts 01b, 03 and 04 were merged into File 1 (create) and File 2 (load), so the database is built with two scripts.

| Core table | What it holds |
|---|---|
| `occupations` | O*NET occupations |
| `skills` | Every skill once. `skill_category` = Technology, Essential or Transferable; `skill_source` = O*NET or Jobicy; `onet_element_id` for Essential and Transferable skills |
| `job_titles` | O*NET alternative titles |
| `occupation_technology_skills` | Technology skills per occupation, with the technology type and the Hot Technology / In Demand flags |
| `occupation_skill_ratings` | Essential and Transferable ratings per occupation (Importance and Level), replacing the two separate rating tables |
| `companies` | Companies from Jobicy postings |
| `job_postings` | Jobicy postings |
| `job_skills` | Jobicy posting ↔ skill links |

The database has **15 tables (7 staging + 8 core)** and two views: `market_skill_demand`, and `occupation_skills`, which lists every occupation–skill pair of any category in one place (importance and level for Essential/Transferable skills; Hot Technology / In Demand flags for Technology skills) without storing anything twice.

Design notes:

- A skill is stored once whatever its type, so O*NET occupations and Jobicy postings point to the same `skill_id`.
- The two occupation link tables hold different facts: a Technology skill is *used* (with Hot Technology / In Demand flags), while an Essential or Transferable skill is *rated* (Importance and Level, with statistics).
- The skill name and scale name are no longer repeated in every rating row. The skill comes from `skills`, and `scale_id` is IM (Importance) or LV (Level).
- `date_updated` was written two ways in the source files ('08/2026' and 'Aug-26'); it is stored as 'YYYY-MM'.
- Jobicy keywords that match an O*NET name exactly (Python, Tableau, PostgreSQL, Snowflake, Docker) reuse that skill. AWS, Java, Power BI and SQL are added with `skill_source = 'Jobicy'`, ready for a later skill-alias step.

**Test build (November 5, MySQL 8.0.46, fresh database):** `skills` = 8,792 (Technology 8,757, Essential 10, Transferable 25); `occupation_technology_skills` = 31,821; `occupation_skill_ratings` = 63,700 (18,200 + 45,500); every validation check = 0. These counts still need to be confirmed on the team's own machines.

## MySQL setup and reproduction

**Requirements:** MySQL 8.0+ (MySQL Community Server, or MAMP 7+ with MySQL 8.0 selected), MySQL Workbench, Python 3 with Pandas, Requests, Beautiful Soup and `mysql-connector-python`, and Jupyter or VS Code for the notebooks.

1. Clone this repository and connect MySQL Workbench to your MySQL server (MAMP uses port 8889 by default, standard MySQL 3306).
2. If you built `jobavenir_db` with the older scripts, run `DROP DATABASE jobavenir_db;` once. This only removes your local copy.
3. Run `sql/JobAvenir_01_Create_Database_MySQL.sql` to create the 15 tables.
4. Import the five O*NET CSVs (occupations, software skills, job titles, essential skills, transferable skills) into their `stg_*` tables with the Table Data Import Wizard.
5. Import the two Jobicy CSVs with `notebooks/importing_jobicy_data_into_MySql.ipynb` (`REPLACE_STAGING = 1`). Clear the notebook's outputs before committing it.
6. Run `sql/JobAvenir_02_Load_and_Analyze_MySQL.sql`. Every validation count should be 0, and the row counts should match `sql/JobAvenir_MySQL_README.txt`.
7. Capture the outputs and screenshots of the CRUD demo and analytical queries for the ADT milestone submission.

**Safety:** Never commit database passwords, `.env` files, or other secrets. GitHub shares source files, **not the running local MySQL database**; teammates need to create their own copy using these scripts and datasets. Pull the latest changes before editing and commit meaningful updates as you go.

## Next steps / progress tracker

| Work item | Status as of Nov 5 |
|---|---|
| Initial 5 source/derived datasets cleaned and prepared | Completed |
| Original MySQL database schema created | Completed |
| Essential Skills and Transferable Skills cleaned | Completed |
| Essential and Transferable CSVs imported into staging | **Verified (18,200 + 45,500)** |
| Skills consolidated into one `skills` table (Files 1 and 2) | Completed; tested on a fresh MySQL 8.0 build |
| Rebuild `jobavenir_db` on team machines and record counts | Pending |
| Skill aliases linking Jobicy keywords to O*NET skills | Planned, after reviewing the loaded data |
| Finalize ER diagram and Milestone 2 report | In progress |
| Implement Streamlit frontend and deployment | Planned |

## References and attribution

- [O*NET Database downloads](https://www.onetcenter.org/database.html) — U.S. Department of Labor, Employment and Training Administration; O*NET 31.0, CC BY 4.0, modified by the project team for data cleaning and relational use.
- [O*NET licensing and attribution](https://www.onetcenter.org/license_db.html)
- [Jobicy API](https://jobicy.com/jobs-rss-feed) — source of sampled remote job postings; preserve attribution and original links when displaying listings.
- [MySQL Workbench documentation](https://dev.mysql.com/doc/workbench/en/)

**AI assistance:** ChatGPT has been used for planning, troubleshooting, code examples, and README drafting. Team members must review and verify all submitted SQL, results, and claims, and disclose meaningful assistance in the course report.
