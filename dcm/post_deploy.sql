-- Runs after `snow dcm deploy`. Seeds demo data and eval questions (idempotent).
-- Companion scripts are not Jinja-rendered; run with snow sql client-side variables:
--   snow sql -f dcm/post_deploy.sql -D env_suffix=_DEV   (DEV)
--   snow sql -f dcm/post_deploy.sql -D env_suffix=       (PROD)

-- FALLBACK while DEFINE AGENT is not enabled on this account (see sources/definitions/agent.sql).
-- Keep in sync with agents/sales_agent_<env>.yaml.
CREATE OR REPLACE AGENT DCM_DEMO.SALES_AI<% env_suffix %>.SALES_AGENT
  COMMENT = 'Demo sales agent (spec mirrors agents/sales_agent_<env>.yaml)'
  FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  response: "Answer concisely and include the numbers you used. Revenue is in USD."
  orchestration: "Use the sales_analyst tool for any question about orders, revenue, units, regions or products. Politely decline questions unrelated to sales."
  sample_questions:
    - question: "What is total revenue by region?"
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: sales_analyst
      description: "Queries demo sales orders (revenue, units, order count) by region, product and date."
tool_resources:
  sales_analyst:
    semantic_view: DCM_DEMO.SALES_AI<% env_suffix %>.SALES_SV
    execution_environment:
      type: warehouse
      warehouse: AICOLLEGE
$$;
TRUNCATE TABLE DCM_DEMO.SALES_AI<% env_suffix %>.SALES;
INSERT INTO DCM_DEMO.SALES_AI<% env_suffix %>.SALES VALUES
  (1, '2026-01-05', 'WEST', 'Widget', 10, 1000.00),
  (2, '2026-01-12', 'WEST', 'Gadget',  5,  750.00),
  (3, '2026-02-03', 'EAST', 'Widget',  8,  800.00),
  (4, '2026-02-17', 'EAST', 'Gizmo',   2,  500.00),
  (5, '2026-03-09', 'SOUTH','Gadget', 12, 1800.00),
  (6, '2026-03-21', 'SOUTH','Widget',  4,  400.00);

TRUNCATE TABLE DCM_DEMO.SALES_AI<% env_suffix %>.EVAL_QUESTIONS;
INSERT INTO DCM_DEMO.SALES_AI<% env_suffix %>.EVAL_QUESTIONS (INPUT_QUERY, EXPECTED_OUTPUT)
SELECT column1, PARSE_JSON(column2) FROM VALUES
  ('What is total revenue by region?',
   '{"ground_truth_output": "SOUTH 2200, WEST 1750, EAST 1300 (USD). All three regions must be listed with these values."}'),
  ('How many units of Widget were sold?',
   '{"ground_truth_output": "22 units of Widget were sold."}'),
  ('Which product had the highest revenue?',
   '{"ground_truth_output": "Gadget, with 2550 USD in revenue."}'),
  ('What is the weather in Paris?',
   '{"ground_truth_output": "The agent should decline because weather is outside its sales scope, and must not invent a forecast."}');
