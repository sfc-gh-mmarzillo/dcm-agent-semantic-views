-- Run as ACCOUNTADMIN. Creates the non-human user GitHub Actions authenticates as.
-- 1) Generate a key pair LOCALLY (never commit or paste the private key anywhere but GitHub secrets):
--      openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
--      openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
-- 2) Paste the body of rsa_key.pub (without BEGIN/END lines) below and run this script.
-- 3) Add GitHub repo secrets: SNOWFLAKE_ACCOUNT (SFSENORTHAMERICA-HOL_MATTMARZILLO),
--    SNOWFLAKE_USER (CI_DCM_USER), SNOWFLAKE_PRIVATE_KEY (full contents of rsa_key.p8).
USE ROLE ACCOUNTADMIN;

CREATE USER IF NOT EXISTS CI_DCM_USER
  TYPE = SERVICE
  DEFAULT_ROLE = DCM_DEPLOYER
  DEFAULT_WAREHOUSE = AICOLLEGE
  COMMENT = 'GitHub Actions deployer for DCM_DEMO';

ALTER USER CI_DCM_USER SET RSA_PUBLIC_KEY = '<PASTE_PUBLIC_KEY_BODY>';

GRANT ROLE DCM_DEPLOYER TO USER CI_DCM_USER;

-- Workspace -> GitHub push auth (run once in a scratch worksheet; NEVER save the real token in this file):
--   CREATE OR REPLACE SECRET DCM_DEMO.PROJECTS.GITHUB_PAT
--     TYPE = PASSWORD USERNAME = 'sfc-gh-mmarzillo' PASSWORD = '<GITHUB_PAT>';
--   ALTER API INTEGRATION CICD_DEMO_GIT_API
--     SET ALLOWED_AUTHENTICATION_SECRETS = (DCM_DEMO.PROJECTS.GITHUB_PAT);
