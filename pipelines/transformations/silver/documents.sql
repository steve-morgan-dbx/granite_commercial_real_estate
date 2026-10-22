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
        "escalation_type":        {"type": "string", "description": "fixed, cpi, or percentage"},
        "escalation_rate":        {"type": "number", "description": "Annual escalation rate as decimal"},
        "renewal_option_count":   {"type": "integer"},
        "has_co_tenancy":         {"type": "boolean"},
        "co_tenancy_terms":       {"type": "string"},
        "has_termination_right":  {"type": "boolean"},
        "termination_right_date": {"type": "string", "description": "Earliest termination date YYYY-MM-DD"},
        "has_exclusive_use":      {"type": "boolean"},
        "exclusive_use_terms":    {"type": "string"},
        "security_deposit":       {"type": "number"},
        "abstract_confidence":    {"type": "number", "description": "Confidence 0-1 in the overall extraction"}
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
  result:response:tenant_name:value::STRING            AS tenant_name,
  result:response:property_address:value::STRING       AS property_address,
  result:response:lease_start:value::STRING            AS lease_start,
  result:response:lease_end:value::STRING              AS lease_end,
  result:response:monthly_rent:value::DOUBLE           AS monthly_rent,
  result:response:annual_base_rent:value::DOUBLE       AS annual_base_rent,
  result:response:escalation_type:value::STRING        AS escalation_type,
  result:response:escalation_rate:value::DOUBLE        AS escalation_rate,
  result:response:renewal_option_count:value::INT      AS renewal_option_count,
  result:response:has_co_tenancy:value::BOOLEAN        AS has_co_tenancy,
  result:response:co_tenancy_terms:value::STRING       AS co_tenancy_terms,
  result:response:has_termination_right:value::BOOLEAN AS has_termination_right,
  result:response:termination_right_date:value::STRING AS termination_right_date,
  result:response:has_exclusive_use:value::BOOLEAN     AS has_exclusive_use,
  result:response:exclusive_use_terms:value::STRING    AS exclusive_use_terms,
  result:response:security_deposit:value::DOUBLE       AS security_deposit,
  result:response:abstract_confidence:value::DOUBLE    AS abstract_confidence,
  parse_timestamp
FROM extracted
WHERE is_variant_null(result:error_message);

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
  result:response:tenant_list:value            AS tenant_list,
  parse_timestamp
FROM extracted
WHERE is_variant_null(result:error_message);
