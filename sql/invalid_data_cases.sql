USE jobavenir_db;
       
-- A: load the same occupation twice (PRIMARY KEY)
INSERT INTO occupations (occupation_id, occupation_title)
SELECT occupation_id, 'Duplicate Test' FROM occupations LIMIT 1;

-- B: link a skill to a job posting that doesn't exist (FOREIGN KEY)
INSERT INTO job_skills (job_id, skill_id)
SELECT '__NONEXISTENT_JOB_ID__', skill_id FROM skills LIMIT 1;

-- C: a skill category that isn't Technology / Essential / Transferable (CHECK)
INSERT INTO skills (skill_name, skill_category)
VALUES ('Demo Skill', 'Other');

-- D: a user rates a skill 9 on a 1-5 scale (CHECK)
INSERT INTO user_skills (user_id, skill_id, proficiency)
SELECT u.user_id, k.skill_id, 9
FROM app_users u
JOIN skills k ON k.skill_name = 'Tableau' AND k.skill_category = 'Technology'
WHERE u.email = 'demo.a@example.com';

-- E: a second sign-up with an email already in use (UNIQUE)
INSERT INTO app_users (display_name, email)
VALUES ('Copy of Demo User A', 'demo.a@example.com');

-- Afterwards: nothing was added (expected 1016, 3, 17)
SELECT (SELECT COUNT(*) FROM occupations) AS occupations,
       (SELECT COUNT(*) FROM app_users)   AS app_users,
       (SELECT COUNT(*) FROM user_skills) AS user_skills;
       