DEFINE SCHEMA DCM_DEMO.SALES_AI{{env_suffix}};

DEFINE TABLE DCM_DEMO.SALES_AI{{env_suffix}}.SALES (
    ORDER_ID   NUMBER,
    ORDER_DATE DATE,
    REGION     VARCHAR,
    PRODUCT    VARCHAR,
    UNITS      NUMBER,
    REVENUE    NUMBER(12,2)
);

-- Eval inputs: one question per row plus a ground-truth JSON rubric
DEFINE TABLE DCM_DEMO.SALES_AI{{env_suffix}}.EVAL_QUESTIONS (
    INPUT_QUERY     VARCHAR,
    EXPECTED_OUTPUT VARIANT
);

-- Holds the agent evaluation config YAML
DEFINE STAGE DCM_DEMO.SALES_AI{{env_suffix}}.EVAL_STAGE
    DIRECTORY = (ENABLE = TRUE);
