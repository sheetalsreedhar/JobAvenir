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
| Jobicy API | `jobicy_jobs_clean.csv` | 79 | Saved sample of job postings and descriptions |
| Derived from Jobicy | `job_skills_clean.csv` | 176 | Extracted job–skill pairs |
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

### 2. Created four MySQL tables

Opened and executed `sql/JobAvenir_03_Add_Essential_Transferable_Skills_MySQL.sql` in MySQL Workbench. This adds:

| Table | Role |
|---|---|
| `stg_essential_skills` | Staging import of 15-column Essential Skills CSV |
| `stg_transferable_skills` | Staging import of 15-column Transferable Skills CSV |
| `essential_skill_ratings` | Final normalized table of Essential Skills ratings |
| `transferable_skill_ratings` | Final normalized table of Transferable Skills ratings |

The two final rating tables omit `occupation_title` (already stored in `occupations`) and have **primary key** (`occupation_id`, `element_id`, `scale_id`) plus a **foreign key** to `occupations(occupation_id)`. Existing original database tables were not recreated. The database now has **16 defined tables: 7 staging + 9 relational**.

### 3. Imported the cleaned CSVs into staging

| CSV | Import destination | **Verified rows** |
|---|---|---:|
| `essential_skills_clean.csv` | `stg_essential_skills` | **18,200** |
| `transferable_skills_clean.csv` | `stg_transferable_skills` | **45,500** |

The following SQL was executed to check table counts:

```sql
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
```

**Last confirmed result (November 5):** `stg_essential_skills` = **18,200**; `stg_transferable_skills` = **45,500**; `essential_skill_ratings` = **0**; `transferable_skill_ratings` = **0**. Thus, the CSVs have been staged **but not yet confirmed loaded into final rating tables**.

### 4. Prepared final loading and validation queries (next to execute)

`sql/JobAvenir_04_Load_Essential_Transferable_Skills_MySQL.sql` provides:

- **Section A:** Validate populated parent `occupations` table, unmatched occupation codes, duplicate composite keys, missing required values, malformed rating values, and invalid Y/N flags.
- **Section B:** Insert valid staged records into `essential_skill_ratings` and `transferable_skill_ratings` in a transaction.
- **Section C:** Compare final counts with staging and test occupation-to-skill SQL joins.

**Do not claim final loading is complete until these statements have run successfully and the final row counts have been verified.** The `occupations` parent table must be populated before either rating table can accept foreign-key references.

## MySQL setup and reproduction

**Requirements:** MySQL Community Server 8.0+, MySQL Workbench, Python 3, Pandas, Requests, Beautiful Soup, and `mysql-connector-python` for Python-based CSV importing.

1. Clone this repository and connect to a local MySQL Community Server in Workbench.
2. Run `sql/JobAvenir_01_Create_Database_MySQL.sql` to create `jobavenir_db` and the original tables.
3. Load the original five cleaned CSV files into the matching `stg_*` tables. If the Workbench wizard fails on long Jobicy descriptions, use the Python MySQL connector to load the CSV safely. Check for partially loaded tables before retrying.
4. Run the **validation then core-loading** steps from `sql/JobAvenir_02_Load_and_Analyze_MySQL.sql` in order; verify key relationships and counts.
5. Run `sql/JobAvenir_03_Add_Essential_Transferable_Skills_MySQL.sql` to create the new rating tables.
6. Import `essential_skills_clean.csv` into `stg_essential_skills` and `transferable_skills_clean.csv` into `stg_transferable_skills`.
7. Run **Section A** of `sql/JobAvenir_04_Load_Essential_Transferable_Skills_MySQL.sql`. Only after the checks pass, run **Section B**, verify both inserts, and commit. Run **Section C** to verify final tables.
8. Execute the prepared CRUD and job-market analytical queries; capture their real outputs for the ADT milestone submission.

**Safety:** Never commit database passwords, `.env` files, or other secrets. GitHub shares source files, **not the running local MySQL database**; teammates need to create their own copy using these scripts and datasets. Pull the latest changes before editing and commit meaningful updates as you go.

## Next steps / progress tracker

| Work item | Status as of Nov 5 |
|---|---|
| Initial 5 source/derived datasets cleaned and prepared | Completed |
| Original MySQL database schema created | Completed |
| Essential Skills and Transferable Skills cleaned | Completed |
| Four new MySQL staging/final rating tables created | Completed |
| Essential and Transferable CSVs imported into staging | **Verified (18,200 + 45,500)** |
| Load data into `essential_skill_ratings` and `transferable_skill_ratings` | **Pending verification (last observed 0 + 0)** |
| Verify all main relational tables / CRUD / analytics | Verify or complete as needed |
| Finalize ER diagram and Milestone 2 report | In progress |
| Implement Streamlit frontend and deployment | Planned |

## References and attribution

- [O*NET Database downloads](https://www.onetcenter.org/database.html) — U.S. Department of Labor, Employment and Training Administration; O*NET 31.0, CC BY 4.0, modified by the project team for data cleaning and relational use.
- [O*NET licensing and attribution](https://www.onetcenter.org/license_db.html)
- [Jobicy API](https://jobicy.com/jobs-rss-feed) — source of sampled remote job postings; preserve attribution and original links when displaying listings.
- [MySQL Workbench documentation](https://dev.mysql.com/doc/workbench/en/)

**AI assistance:** ChatGPT has been used for planning, troubleshooting, code examples, and README drafting. Team members must review and verify all submitted SQL, results, and claims, and disclose meaningful assistance in the course report.
