-- ============================================================================
-- JobAvenir | MySQL 8.0+
-- FILE 3: Add O*NET Essential Skills and Transferable Skills tables
-- Run after JobAvenir_01_Create_Database_MySQL.sql.
-- Does NOT delete, empty, or alter existing JobAvenir tables.
-- ============================================================================

USE jobavenir_db;

-- Staging tables match the seven-column-renamed 15-field CSV exports:
-- occupation_id,occupation_title,element_id,skill_name,scale_id,scale_name,
-- data_value,sample_size,standard_error,lower_ci_bound,upper_ci_bound,
-- recommend_suppress,not_relevant,date_updated,domain_source
-- Numeric fields are stored as VARCHAR in staging so you can inspect source
-- values and blanks before loading the strictly typed core tables.

CREATE TABLE IF NOT EXISTS stg_essential_skills (
    occupation_id        VARCHAR(20),
    occupation_title     VARCHAR(500),
    element_id           VARCHAR(20),
    skill_name           VARCHAR(255),
    scale_id             VARCHAR(3),
    scale_name           VARCHAR(50),
    data_value           VARCHAR(40),
    sample_size          VARCHAR(40),
    standard_error       VARCHAR(40),
    lower_ci_bound       VARCHAR(40),
    upper_ci_bound       VARCHAR(40),
    recommend_suppress   VARCHAR(5),
    not_relevant         VARCHAR(5),
    date_updated         VARCHAR(7),
    domain_source        VARCHAR(30)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS stg_transferable_skills (
    occupation_id        VARCHAR(20),
    occupation_title     VARCHAR(500),
    element_id           VARCHAR(20),
    skill_name           VARCHAR(255),
    scale_id             VARCHAR(3),
    scale_name           VARCHAR(50),
    data_value           VARCHAR(40),
    sample_size          VARCHAR(40),
    standard_error       VARCHAR(40),
    lower_ci_bound       VARCHAR(40),
    upper_ci_bound       VARCHAR(40),
    recommend_suppress   VARCHAR(5),
    not_relevant         VARCHAR(5),
    date_updated         VARCHAR(7),
    domain_source        VARCHAR(30)
) ENGINE=InnoDB;

-- Core tables use the existing occupations table as the parent.
-- (occupation_id, element_id, scale_id) uniquely identifies one rating.
-- Two scales per occupation/skill are separate valid records.
-- Occupation title is not duplicated here; retrieve it using a JOIN.
-- Preserve O*NET's date as text (e.g., MM/YYYY), not a MySQL DATE.

CREATE TABLE IF NOT EXISTS essential_skill_ratings (
    occupation_id        VARCHAR(20) NOT NULL,
    element_id           VARCHAR(20) NOT NULL,
    skill_name           VARCHAR(255) NOT NULL,
    scale_id             VARCHAR(3) NOT NULL,
    scale_name           VARCHAR(50),
    data_value           DECIMAL(5,2),
    sample_size          INT UNSIGNED,
    standard_error       DECIMAL(7,4),
    lower_ci_bound       DECIMAL(7,4),
    upper_ci_bound       DECIMAL(7,4),
    recommend_suppress   CHAR(1),
    not_relevant         CHAR(1),
    date_updated         VARCHAR(7),
    domain_source        VARCHAR(30),
    PRIMARY KEY (occupation_id, element_id, scale_id),
    KEY idx_essential_skill (element_id, scale_id),
    CONSTRAINT fk_essential_occupation
        FOREIGN KEY (occupation_id) REFERENCES occupations(occupation_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT chk_essential_suppress
        CHECK (recommend_suppress IS NULL OR recommend_suppress IN ('Y','N')),
    CONSTRAINT chk_essential_relevant
        CHECK (not_relevant IS NULL OR not_relevant IN ('Y','N'))
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS transferable_skill_ratings (
    occupation_id        VARCHAR(20) NOT NULL,
    element_id           VARCHAR(20) NOT NULL,
    skill_name           VARCHAR(255) NOT NULL,
    scale_id             VARCHAR(3) NOT NULL,
    scale_name           VARCHAR(50),
    data_value           DECIMAL(5,2),
    sample_size          INT UNSIGNED,
    standard_error       DECIMAL(7,4),
    lower_ci_bound       DECIMAL(7,4),
    upper_ci_bound       DECIMAL(7,4),
    recommend_suppress   CHAR(1),
    not_relevant         CHAR(1),
    date_updated         VARCHAR(7),
    domain_source        VARCHAR(30),
    PRIMARY KEY (occupation_id, element_id, scale_id),
    KEY idx_transferable_skill (element_id, scale_id),
    CONSTRAINT fk_transferable_occupation
        FOREIGN KEY (occupation_id) REFERENCES occupations(occupation_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT chk_transferable_suppress
        CHECK (recommend_suppress IS NULL OR recommend_suppress IN ('Y','N')),
    CONSTRAINT chk_transferable_relevant
        CHECK (not_relevant IS NULL OR not_relevant IN ('Y','N'))
) ENGINE=InnoDB;

-- Confirm the new tables exist. Counts remain 0 until CSVs are imported.
SHOW TABLES FROM jobavenir_db;
DESCRIBE essential_skill_ratings;
DESCRIBE transferable_skill_ratings;

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
