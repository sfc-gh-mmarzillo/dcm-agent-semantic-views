DEFINE SEMANTIC VIEW DCM_DEMO.SALES_AI{{env_suffix}}.SALES_SV
  TABLES (
    sales AS DCM_DEMO.SALES_AI{{env_suffix}}.SALES
      PRIMARY KEY (ORDER_ID)
      WITH SYNONYMS = ('orders', 'transactions')
      COMMENT = 'One row per order'
  )
  FACTS (
    sales.UNITS_FACT   AS sales.UNITS,
    sales.REVENUE_FACT AS sales.REVENUE
  )
  DIMENSIONS (
    sales.ORDER_DATE AS sales.ORDER_DATE COMMENT = 'Date the order was placed',
    sales.REGION     AS sales.REGION     WITH SYNONYMS = ('territory'),
    sales.PRODUCT    AS sales.PRODUCT    WITH SYNONYMS = ('item', 'sku')
  )
  METRICS (
    sales.TOTAL_REVENUE AS SUM(sales.REVENUE_FACT) COMMENT = 'Total revenue in USD',
    sales.TOTAL_UNITS   AS SUM(sales.UNITS_FACT),
    sales.ORDER_COUNT   AS COUNT(sales.ORDER_ID)
  )
  COMMENT = 'Demo sales semantic view managed by DCM'
  AI_VERIFIED_QUERIES (
    revenue_by_region AS (
      QUESTION 'What is total revenue by region?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(DCM_DEMO.SALES_AI{{env_suffix}}.SALES_SV METRICS sales.TOTAL_REVENUE DIMENSIONS sales.REGION) ORDER BY total_revenue DESC'
    )
  );
