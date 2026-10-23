-- Silver: document intelligence — ai_parse_document + ai_extract
-- These are materialized views (batch) since AI functions process each doc once per refresh.

-- ── Lease documents ────────────────────────────────────────────────

CREATE OR REFRESH MATERIALIZED VIEW silver_lease_text AS
SELECT
  path,
  regexp_extract(path, '(GP-LSE-\\d+)', 1) AS lease_id,
  ai_parse_document(content, MAP('version', '2.0')) AS parsed_content,
  current_timestamp() AS parse_timestamp
FROM bronze_lease_docs;

CREATE OR REFRESH MATERIALIZED VIEW silver_lease_extract AS
WITH extracted AS (
  SELECT
    path,
    lease_id,
    ai_extract(
      parsed_content,
      '{
        "tenant_name":            {"type": "string"},
        "property_address":       {"type": "string"},
        "lease_start":            {"type": "string", "description": "Lease start date YYYY-MM-DD"},
        "lease_end":              {"type": "string", "description": "Lease end date YYYY-MM-DD"},
        "monthly_rent":           {"type": "number"},
        "annual_base_rent":       {"type": "number"},
        "escalation_type":        {"type": "string", "description": "One of: Fixed, CPI, Stepped"},
        "escalation_rate":        {"type": "number", "description": "Annual escalation rate as decimal"},
        "renewal_option_count":   {"type": "integer"},
        "has_co_tenancy":         {"type": "boolean"},
        "co_tenancy_terms":       {"type": "string"},
        "has_termination_right":  {"type": "boolean"},
        "termination_right_date": {"type": "string", "description": "Earliest termination date YYYY-MM-DD"},
        "has_exclusive_use":      {"type": "boolean"},
        "exclusive_use_terms":    {"type": "string"},
        "security_deposit":       {"type": "number"}
      }',
      MAP('version', '2.1',
          'instructions', 'Extract lease terms from a commercial real estate lease agreement. Dates in YYYY-MM-DD. Monetary values in USD without currency symbols.')
    ) AS result,
    parse_timestamp
  FROM silver_lease_text
)
SELECT
  path,
  lease_id,
  tenant_name, property_address, lease_start, lease_end, monthly_rent, annual_base_rent,
  escalation_type, escalation_rate, renewal_option_count, has_co_tenancy, co_tenancy_terms,
  has_termination_right, termination_right_date, has_exclusive_use, exclusive_use_terms, security_deposit,
  -- Share of the eight fields every lease must state; < 1.0 sends the abstract to analyst review.
  -- Clause flags are excluded: a lease without a co-tenancy article legitimately has none.
  round((
      CAST(tenant_name IS NOT NULL AS INT) + CAST(property_address IS NOT NULL AS INT)
    + CAST(lease_start IS NOT NULL AS INT) + CAST(lease_end IS NOT NULL AS INT)
    + CAST(monthly_rent IS NOT NULL AS INT) + CAST(annual_base_rent IS NOT NULL AS INT)
    + CAST(escalation_type IS NOT NULL AS INT) + CAST(security_deposit IS NOT NULL AS INT)
  ) / 8.0, 2) AS abstract_confidence,
  parse_timestamp
FROM (
  SELECT
    path,
    lease_id,
    result:response:tenant_name:value::STRING                         AS tenant_name,
    result:response:property_address:value::STRING                    AS property_address,
    try_to_date(result:response:lease_start:value::STRING)            AS lease_start,
    try_to_date(result:response:lease_end:value::STRING)              AS lease_end,
    result:response:monthly_rent:value::DOUBLE                        AS monthly_rent,
    result:response:annual_base_rent:value::DOUBLE                    AS annual_base_rent,
    result:response:escalation_type:value::STRING                     AS escalation_type,
    result:response:escalation_rate:value::DOUBLE                     AS escalation_rate,
    coalesce(result:response:renewal_option_count:value::INT, 0)      AS renewal_option_count,
    coalesce(result:response:has_co_tenancy:value::BOOLEAN, false)    AS has_co_tenancy,
    result:response:co_tenancy_terms:value::STRING                    AS co_tenancy_terms,
    coalesce(result:response:has_termination_right:value::BOOLEAN, false) AS has_termination_right,
    try_to_date(result:response:termination_right_date:value::STRING) AS termination_right_date,
    coalesce(result:response:has_exclusive_use:value::BOOLEAN, false) AS has_exclusive_use,
    result:response:exclusive_use_terms:value::STRING                 AS exclusive_use_terms,
    result:response:security_deposit:value::DOUBLE                    AS security_deposit,
    parse_timestamp
  FROM extracted
  WHERE is_variant_null(result:error_message)
);

-- ── Deal documents ─────────────────────────────────────────────────

CREATE OR REFRESH MATERIALIZED VIEW silver_deal_text AS
SELECT
  path,
  regexp_extract(path, '(GP-ACQ-\\d+)', 1) AS deal_id,
  regexp_extract(path, 'GP-ACQ-\\d+_(\\w+)\\.pdf', 1) AS doc_type,
  ai_parse_document(content, MAP('version', '2.0')) AS parsed_content,
  current_timestamp() AS parse_timestamp
FROM bronze_deal_docs;

CREATE OR REFRESH MATERIALIZED VIEW silver_deal_extract AS
WITH extracted AS (
  SELECT
    path,
    deal_id,
    doc_type,
    ai_extract(
      parsed_content,
      '{
        "asking_price":  {"type": "number"},
        "noi":           {"type": "number"},
        "cap_rate":      {"type": "number", "description": "Cap rate as decimal e.g. 0.065"},
        "irr":           {"type": "number", "description": "Target IRR as decimal"},
        "sqft":          {"type": "integer"},
        "year_built":    {"type": "integer"},
        "tenant_list": {
          "type": "array",
          "description": "List of in-place tenants from the rent roll or offering memorandum",
          "items": {
            "type": "object",
            "properties": {
              "tenant_name":      {"type": "string"},
              "abr":              {"type": "number", "description": "Annual base rent"},
              "lease_end":        {"type": "string", "description": "Lease end YYYY-MM-DD"},
              "renewal_options":  {"type": "integer"},
              "has_co_tenancy":   {"type": "boolean"},
              "co_tenancy_terms": {"type": "string"}
            }
          }
        }
      }',
      MAP('version', '2.1',
          'instructions', 'Extract deal financials and tenant details from a CRE offering memorandum or rent roll. Monetary values in USD.')
    ) AS result,
    parse_timestamp
  FROM silver_deal_text
)
SELECT
  path,
  deal_id,
  doc_type,
  result:response:asking_price:value::DOUBLE   AS asking_price,
  result:response:noi:value::DOUBLE            AS noi,
  result:response:cap_rate:value::DOUBLE       AS cap_rate,
  result:response:irr:value::DOUBLE            AS irr,
  result:response:sqft:value::INT              AS sqft,
  result:response:year_built:value::INT        AS year_built,
  -- Arrays come back as [{field: {value: ...}}, ...] with no outer value wrapper
  transform(cast(result:response:tenant_list AS ARRAY<VARIANT>), t -> named_struct(
    'tenant_name',      t:tenant_name:value::STRING,
    'abr',              t:abr:value::DOUBLE,
    'lease_end',        try_to_date(t:lease_end:value::STRING),
    'renewal_options',  coalesce(t:renewal_options:value::INT, 0),
    'has_co_tenancy',   coalesce(t:has_co_tenancy:value::BOOLEAN, false),
    'co_tenancy_terms', t:co_tenancy_terms:value::STRING
  ))                                           AS tenant_list,
  parse_timestamp
FROM extracted
WHERE is_variant_null(result:error_message);
