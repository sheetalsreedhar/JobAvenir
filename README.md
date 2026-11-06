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
| Jobicy API | `jobicy_jobs_clean.csv` | 845 (pulls of 31 Oct and 6 Nov) | Saved job postings and descriptions; grows with each new pull |
| Derived from Jobicy | `job_skills_clean.csv` | 580 | Extracted job–skill pairs |
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

The database has **18 tables (7 staging + 11 core, including `skill_aliases`, `app_users` and `user_skills` added later the same day)** and two views: `market_skill_demand`, and `occupation_skills`, which lists every occupation–skill pair of any category in one place (importance and level for Essential/Transferable skills; Hot Technology / In Demand flags for Technology skills) without storing anything twice.

Design notes:

- A skill is stored once whatever its type, so O*NET occupations and Jobicy postings point to the same `skill_id`.
- The two occupation link tables hold different facts: a Technology skill is *used* (with Hot Technology / In Demand flags), while an Essential or Transferable skill is *rated* (Importance and Level, with statistics).
- The skill name and scale name are no longer repeated in every rating row. The skill comes from `skills`, and `scale_id` is IM (Importance) or LV (Level).
- `date_updated` was written two ways in the source files ('08/2026' and 'Aug-26'); it is stored as 'YYYY-MM'.
- Jobicy keywords that match an O*NET name exactly (Python, Tableau, PostgreSQL, Snowflake, Docker, Microsoft Excel) reuse that skill; the others are linked through `skill_aliases` (next section).

**Test build (November 5, MySQL 8.0.46, fresh database):** `occupation_technology_skills` = 31,821; `occupation_skill_ratings` = 63,700 (18,200 + 45,500); every validation check = 0. Rebuilt on Mounika's machine (MAMP, MySQL 8.0) the same evening.

## November 5, 2026 — Broader Jobicy collection and skill aliases

**Collection without role tags.** Notebook 02 no longer searches five role tags. Each pull makes one search for all U.S.-eligible jobs plus one search per Jobicy industry (16), following `nextCursor` pages, and saves every response under `data/jobicy/raw/<UTC time>/`. Cleaning combines all pulls, so the dataset grows with each pull; the 31 Oct pull is kept. Jobicy asks for at most one pull per hour, and the notebook refuses to start a pull within an hour of the last one. Because postings from every industry now arrive, File 2 labels postings that match no role rule as `Other Tech` (technical title or tech industry) or `Non-Tech`.

**Skill aliases.** A new `skill_aliases` table maps each Jobicy keyword whose O*NET name differs to that O*NET skill:

| Jobicy keyword | O*NET skill |
|---|---|
| SQL | Structured query language SQL |
| AWS | Amazon Web Services AWS software |
| Power BI | Microsoft Power BI |
| Java | Oracle Java |

Postings and occupations now share one `skill_id` for each of these, so there are no Jobicy-only skills (`skills` = 8,788) and posting mentions can be compared with O*NET's Hot Technology / In Demand flags (File 2, analytical query 8). An existing database needs no rebuild: run File 1 again (it adds `skill_aliases`) and then File 2, which moves any old Jobicy-only skill links onto the O*NET skills.

**First broad pull (6 Nov 2026, 01:34 UTC):** 27 saved responses. Combined with the 31 Oct pull: **845 unique postings** (771 new) from 219 companies, 601 with a salary range, and 580 job–skill links. File 2 classifies 341 postings as tech (227 Other Tech plus the five named roles) and 504 as Non-Tech. Seniority is skewed toward Senior (360) and Director (306) postings.

## November 5, 2026 — User profiles for the skill-gap feature

The planned app lets a user pick a target occupation and see which skills they still need. Two tables store that:

| Table | What it holds |
|---|---|
| `app_users` | A user: display name, unique email, target occupation (FK to `occupations`), `is_demo` flag |
| `user_skills` | The skills a user has (FK to `skills`), with a self-rated proficiency from 1 to 5 |

Until the app exists, File 2 loads **three synthetic demo profiles** (`is_demo = 1`, example.com addresses) aiming at Data Scientists, Software Developers and Business Intelligence Analysts. They are used by:

- **CRUD demo (File 2 Step 13):** create a profile with skills, read it, change its target occupation and a proficiency, then delete it (the delete cascades to its skills). Everything is rolled back.
- **Skill-gap queries (analytical queries 9 and 10):** the skills a user's target occupation needs (importance ≥ 3.5, or a Technology skill marked In Demand) that the user lacks, ranked by how often job postings mention them, and each user's readiness percentage.
- **Invalid-data demos (Step 14):** a proficiency outside 1–5 and a duplicate email are rejected, alongside the duplicate key, invalid foreign key and invalid skill category cases.

The database diagram is in `docs/JobAvenir_ERD.png` (source: `docs/JobAvenir_ERD.mmd`).

## MySQL setup and reproduction

**Requirements:** MySQL 8.0+ (MySQL Community Server, or MAMP 7+ with MySQL 8.0 selected), MySQL Workbench, Python 3, and Jupyter or VS Code for the notebooks. Install the Python packages with `python -m pip install -r requirements.txt` (Pandas, Requests, Beautiful Soup, `mysql-connector-python`, ipykernel).

1. Clone this repository and connect MySQL Workbench to your MySQL server (MAMP uses port 8889 by default, standard MySQL 3306).
2. If you built `jobavenir_db` with the older scripts, run `DROP DATABASE jobavenir_db;` once. This only removes your local copy.
3. Run `sql/JobAvenir_01_Create_Database_MySQL.sql` to create the 18 tables.
4. Import the five O*NET CSVs (occupations, software skills, job titles, essential skills, transferable skills) with `notebooks/importing_onet_data_into_MySql.ipynb`. If your MySQL server is not on port 3306 (MAMP uses 8889), first create a `.env` file in the project folder containing `MYSQL_PORT=8889`; `.env` is not committed, so each teammate keeps their own port. The notebook takes a few seconds, empties each staging table first, and checks every count against its CSV. The Workbench Table Data Import Wizard also works, but it is slow on these files, and an import that is stopped or run twice leaves wrong counts.
5. Import the two Jobicy CSVs with `notebooks/importing_jobicy_data_into_MySql.ipynb` (`REPLACE_STAGING = 1`; it reads the same `.env`). Clear both notebooks' outputs before committing them.
6. Run `sql/JobAvenir_02_Load_and_Analyze_MySQL.sql`. Every validation count should be 0, and the row counts should match `sql/JobAvenir_MySQL_README.txt`.
7. Capture the outputs and screenshots of the CRUD demo and analytical queries for the ADT milestone submission.

**Collecting new Jobicy postings:** in `notebooks/02_Jobicy_Data_Collection.ipynb`, set `COLLECT_NEW_DATA = 1` and run all cells (at most once per hour; a few pulls a day is plenty). It saves the new raw responses and rewrites `jobicy_jobs_clean.csv` and `job_skills_clean.csv` with every pull combined. Then repeat steps 5 and 6. Set `COLLECT_NEW_DATA` back to 0 before committing, and commit the new `data/jobicy/raw/<UTC time>/` folder with the cleaned CSVs.

**Safety:** Never commit database passwords, `.env` files, or other secrets. GitHub shares source files, **not the running local MySQL database**; teammates need to create their own copy using these scripts and datasets. Pull the latest changes before editing and commit meaningful updates as you go.

## Next steps / progress tracker

| Work item | Status as of Nov 5 |
|---|---|
| Initial 5 source/derived datasets cleaned and prepared | Completed |
| Original MySQL database schema created | Completed |
| Essential Skills and Transferable Skills cleaned | Completed |
| Essential and Transferable CSVs imported into staging | **Verified (18,200 + 45,500)** |
| Skills consolidated into one `skills` table (Files 1 and 2) | Completed; tested on a fresh MySQL 8.0 build |
| Rebuild `jobavenir_db` on team machines and record counts | Done on Mounika's machine; Sheetal pending |
| Skill aliases linking Jobicy keywords to O*NET skills | Completed (4 aliases; no Jobicy-only skills) |
| Jobicy collection without role tags (all U.S.-eligible jobs, every industry) | Completed; first broad pull 6 Nov (845 postings in total) |
| User tables (`app_users`, `user_skills`), demo profiles, user-profile CRUD, skill-gap queries | Completed; tested on a fresh MySQL 8.0 build |
| ER diagram (`docs/JobAvenir_ERD.png`) | Completed |
| Milestone 2 report (screenshots, write-up, contributions) | In progress |
| Implement Streamlit frontend and deployment | Planned |

## References and attribution

- [O*NET Database downloads](https://www.onetcenter.org/database.html) — U.S. Department of Labor, Employment and Training Administration; O*NET 31.0, CC BY 4.0, modified by the project team for data cleaning and relational use.
- [O*NET licensing and attribution](https://www.onetcenter.org/license_db.html)
- [Jobicy API](https://jobicy.com/jobs-rss-feed) — source of sampled remote job postings; preserve attribution and original links when displaying listings.
- [MySQL Workbench documentation](https://dev.mysql.com/doc/workbench/en/)


