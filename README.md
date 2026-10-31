# dcm-agent-semantic-views

Minimal, realistic demo: **a Semantic View and a Cortex Agent deployed with DCM Projects**,
with **agent evals as a CI gate**, using a PR → DEV → merge → PROD GitOps flow.
Open `demo_overview.html` for the visual walkthrough.

## Flow

```
feature branch (Workspace) ──commit/push──► PR to main
                                             │  .github/workflows/pr.yml
                                             ├─ snow dcm raw-analyze   (DEV + PROD)  syntax, deps, lineage
                                             ├─ snow dcm plan          (DEV + PROD preview) → PR comment
                                             ├─ snow dcm deploy DEV    --alias pr-<n>-<sha>
                                             ├─ snow sql post_deploy   (agent, seed data, eval questions)
                                             └─ ci/run_evals.py        EXECUTE_AI_EVALUATION, fail if avg < 0.75
reviewer approves + merges ──────────────────┐
                                             │  .github/workflows/deploy-prod.yml
                                             └─ (production env approval) plan → deploy PROD --alias main-<sha> → post_deploy
```

| | DEV (PRs) | PROD (main) |
|---|---|---|
| DCM project | `DCM_DEMO.PROJECTS.AGENT_SV_DEMO_DEV` | `DCM_DEMO.PROJECTS.AGENT_SV_DEMO_PROD` |
| Objects | `DCM_DEMO.SALES_AI_DEV.*` | `DCM_DEMO.SALES_AI.*` |

## Layout

```
setup.sql                         one-time: DB/schema, DCM_DEPLOYER role, DEV + PROD projects
dcm/
  manifest.yml                    DEV/PROD targets, env_suffix templating, agent assets
  sources/definitions/
    infra.sql                     schema, SALES table, EVAL_QUESTIONS table, EVAL_STAGE
    semantic.sql                  DEFINE SEMANTIC VIEW SALES_SV (+ verified query)
    agent.sql                     DEFINE AGENT ... FROM SPECIFICATION 'asset://...' (commented, see below)
  agents/sales_agent_{dev,prod}.yaml   agent spec (assets are not Jinja-rendered → one per env)
  post_deploy.sql                 agent fallback + seed data + eval questions (snow sql -D vars)
evals/sales_agent_eval.yaml       resolved EXECUTE_AI_EVALUATION config (answer_correctness, logical_consistency)
ci/run_evals.py                   dataset snapshot → start eval → poll → score gate
ci/create_ci_user.sql             CI service user (key-pair auth)
.github/                          pr.yml, deploy-prod.yml, shared snow-setup action
demo_overview.html                visual walkthrough for presenting
```

## One-time setup

1. Run `setup.sql` as ACCOUNTADMIN.
2. Generate a key pair locally and run `ci/create_ci_user.sql` (instructions inside).
3. GitHub repo → Settings:
   - **Secrets:** `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PRIVATE_KEY`
   - **Environments:** create `production` with required reviewers (gates the PROD deploy)
   - **Branch protection on `main`:** require the *PR - DCM validate, deploy DEV, eval* check

Never save tokens or private keys in files in this repo. Run credential SQL in an unsaved scratch worksheet.

## Run it manually (same steps CI runs)

```bash
cd dcm
snow dcm raw-analyze -c default --role DCM_DEPLOYER --target DEV
snow dcm plan        -c default --role DCM_DEPLOYER --target DEV
snow dcm deploy      -c default --role DCM_DEPLOYER --target DEV --alias my-change
cd ..
snow sql -c default --role DCM_DEPLOYER -f dcm/post_deploy.sql -D env_suffix=_DEV
SNOWFLAKE_CONNECTION=default python ci/run_evals.py --run-name my_change
```

Results also show in Snowsight: AI & ML → Agents → SALES_AGENT → Evaluations.

## Try the loop

- **Break it:** change the agent's `orchestration` instruction to "never use tools" in
  `dcm/post_deploy.sql` and open a PR → evals drop and the check fails.
- **Grow it:** add a metric to `semantic.sql` and a matching question to `EVAL_QUESTIONS`
  in `post_deploy.sql` → the PR comment shows the semantic view ALTER, and evals cover it.

## Preview caveats (per the DCM SV/Agents PuPr doc)

- **`DEFINE AGENT` is Private Preview and not enabled on this account** (`raw-analyze` returns
  `unexpected 'AGENT'`). Until it is, the agent is created in `post_deploy.sql`. When it is enabled,
  uncomment `dcm/sources/definitions/agent.sql` and delete the `CREATE AGENT` block → the agent
  becomes a planned/versioned DCM entity like the semantic view.
- **Project assets are not Jinja-rendered**, so agent specs are duplicated per environment.
- **Semantic view from a YAML asset is only proposed**, so the semantic view is defined inline in SQL.
- **Evals aren't DCM objects.** DCM owns the eval table and stage; the run itself is an imperative CI step.
- **Demo seed data is reloaded on every deploy.** Remove the seed inserts before pointing this at real tables.
