-- Gold layer: portfolio-facing materialized views
-- ${as_of_date} and ${uc_schema} are set in the pipeline configuration (see resources/pipeline.yml).
-- The row-filter and mask functions are created by notebooks/03_governance.ipynb before the pipeline runs.

-- ── property_h3: properties with H3 indices ──────────────────────────────────

CREATE OR REFRESH MATERIALIZED VIEW property_h3
COMMENT 'Properties with H3 res-9 (~175 m edge) and res-7 cells'
AS SELECT
  p.*,
  CASE
    WHEN p.state IN ('WA', 'OR', 'ID') THEN 'Pacific Northwest'
    WHEN p.state IN ('UT', 'CO', 'NM') THEN 'Mountain'
    ELSE 'Southwest'
  END AS region,
  h3_longlatash3(p.lon, p.lat, 9)  AS h3_res9,
  h3_longlatash3(p.lon, p.lat, 7)  AS h3_res7
FROM silver_property p;

-- ── lease_abstract: fields extracted from lease PDFs, with analyst corrections ─
-- Approved corrections come from abstract_review (written by the app to Lakebase, copied to Delta).

CREATE OR REFRESH MATERIALIZED VIEW lease_abstract
COMMENT 'Lease terms extracted from lease PDFs with ai_parse_document + ai_extract; approved analyst corrections override extracted values'
AS WITH corrections AS (
  SELECT lease_id,
         max_by(corrected_value, reviewed_at) FILTER (WHERE field_name = 'tenant_name')            AS tenant_name,
         max_by(corrected_value, reviewed_at) FILTER (WHERE field_name = 'lease_end')              AS lease_end,
         max_by(corrected_value, reviewed_at) FILTER (WHERE field_name = 'monthly_rent')           AS monthly_rent,
         max_by(corrected_value, reviewed_at) FILTER (WHERE field_name = 'renewal_option_count')   AS renewal_option_count,
         max_by(corrected_value, reviewed_at) FILTER (WHERE field_name = 'has_co_tenancy')         AS has_co_tenancy,
         max_by(corrected_value, reviewed_at) FILTER (WHERE field_name = 'has_termination_right')  AS has_termination_right,
         max_by(corrected_value, reviewed_at) FILTER (WHERE field_name = 'termination_right_date') AS termination_right_date,
         count(*)                                                                                  AS corrected_fields,
         max(reviewed_at)                                                                          AS last_reviewed_at
  FROM ${uc_schema}.abstract_review
  WHERE status = 'approved'
  GROUP BY lease_id
)
SELECT
  le.path,
  le.lease_id,
  coalesce(c.tenant_name, le.tenant_name)                                         AS tenant_name,
  le.property_address,
  le.lease_start,
  coalesce(try_to_date(c.lease_end), le.lease_end)                                AS lease_end,
  coalesce(try_cast(c.monthly_rent AS DOUBLE), le.monthly_rent)                   AS monthly_rent,
  le.annual_base_rent,
  le.escalation_type,
  le.escalation_rate,
  coalesce(try_cast(c.renewal_option_count AS INT), le.renewal_option_count)      AS renewal_option_count,
  coalesce(try_cast(c.has_co_tenancy AS BOOLEAN), le.has_co_tenancy)              AS has_co_tenancy,
  le.co_tenancy_terms,
  coalesce(try_cast(c.has_termination_right AS BOOLEAN), le.has_termination_right) AS has_termination_right,
  coalesce(try_to_date(c.termination_right_date), le.termination_right_date)      AS termination_right_date,
  le.has_exclusive_use,
  le.exclusive_use_terms,
  le.security_deposit,
  le.abstract_confidence,
  CASE WHEN c.lease_id IS NOT NULL THEN 'corrected'
       WHEN le.abstract_confidence < 1 THEN 'needs_review'
       ELSE 'extracted' END                                                       AS review_status,
  coalesce(c.corrected_fields, 0)                                                 AS corrected_fields,
  c.last_reviewed_at,
  le.parse_timestamp
FROM silver_lease_extract le
LEFT JOIN corrections c ON le.lease_id = c.lease_id;

-- ── rent_roll: active leases, ERP terms + document-derived clauses ───────────

CREATE OR REFRESH MATERIALIZED VIEW rent_roll (
  lease_id               STRING  COMMENT 'ERP lease identifier (GP-LSE-#####)',
  property_id            STRING  COMMENT 'Property identifier (GP-PROP-####)',
  unit_id                STRING  COMMENT 'Unit identifier',
  tenant_id              STRING  COMMENT 'Tenant identifier',
  fund_id                STRING  COMMENT 'Owning fund (GP-FND-001 = GP Fund I ... GP-FND-004 = GP Opportunity IV); rows are filtered by fund entitlement',
  property_name          STRING  COMMENT 'Property name',
  property_type          STRING  COMMENT 'Office, Retail or Industrial',
  city                   STRING  COMMENT 'City (same as MSA name)',
  state                  STRING  COMMENT 'Two-letter state code',
  msa                    STRING  COMMENT 'Metropolitan statistical area',
  region                 STRING  COMMENT 'Pacific Northwest (WA, OR, ID), Mountain (UT, CO, NM) or Southwest (AZ, NV)',
  unit_number            STRING  COMMENT 'Suite / unit number',
  unit_sqft              BIGINT  COMMENT 'Leased square feet',
  tenant_name            STRING  COMMENT 'Tenant legal name',
  industry               STRING  COMMENT 'Tenant industry',
  credit_rating          STRING  COMMENT 'Tenant credit rating (AAA to B)',
  lease_start            DATE    COMMENT 'Lease commencement date (ERP)',
  lease_end              DATE    COMMENT 'Lease expiration date (ERP)',
  months_to_expiry       DOUBLE  COMMENT 'Months from the reporting date to lease_end',
  monthly_rent           DOUBLE  COMMENT 'Monthly base rent in USD (ERP)',
  annual_base_rent       DOUBLE  COMMENT 'Annualized base rent (ABR) in USD (ERP)',
  escalation_type        STRING  COMMENT 'Fixed, CPI or Stepped rent escalation (ERP)',
  renewal_option_count   INT     COMMENT 'Number of renewal options, from the lease document; NULL when has_abstract is false',
  has_co_tenancy         BOOLEAN COMMENT 'Lease has a co-tenancy clause, from the lease document; NULL when has_abstract is false',
  has_termination_right  BOOLEAN COMMENT 'Tenant has an early termination right, from the lease document; NULL when has_abstract is false',
  termination_right_date DATE    COMMENT 'Earliest date the tenant may terminate, from the lease document',
  has_exclusive_use      BOOLEAN COMMENT 'Lease grants an exclusive use, from the lease document; NULL when has_abstract is false',
  has_abstract           BOOLEAN COMMENT 'True when the lease PDF has been abstracted (active leases expiring within 24 months plus the 25 largest by ABR)'
)
CLUSTER BY (fund_id, property_id)
COMMENT 'Active leases as of the reporting date. Clause columns come from lease documents and are NULL when the lease has no abstract (has_abstract = false)'
WITH ROW FILTER ${uc_schema}.fund_row_filter ON (fund_id)
AS SELECT
  cl.lease_id,
  cl.property_id,
  cl.unit_id,
  cl.tenant_id,
  p.fund_id,
  p.property_name,
  p.property_type,
  p.city,
  p.state,
  p.msa,
  p.region,
  u.unit_number,
  u.sqft                                AS unit_sqft,
  t.tenant_name,
  t.industry,
  t.credit_rating,
  CAST(cl.lease_start AS DATE)          AS lease_start,
  CAST(cl.lease_end AS DATE)            AS lease_end,
  months_between(CAST(cl.lease_end AS DATE), DATE'${as_of_date}') AS months_to_expiry,
  cl.monthly_rent,
  cl.annual_base_rent,
  cl.escalation_type,
  le.renewal_option_count,
  le.has_co_tenancy,
  le.has_termination_right,
  le.termination_right_date,
  le.has_exclusive_use,
  le.lease_id IS NOT NULL               AS has_abstract
FROM silver_commlease cl
JOIN property_h3 p     ON cl.property_id = p.property_id
JOIN silver_unit u     ON cl.unit_id = u.unit_id
JOIN silver_tenant t   ON cl.tenant_id = t.tenant_id
LEFT JOIN lease_abstract le ON cl.lease_id = le.lease_id
WHERE cl.lease_status = 'Active';

-- ── tenant_directory: tenant master with masked contact details ─────────────

CREATE OR REFRESH MATERIALIZED VIEW tenant_directory (
  tenant_id     STRING COMMENT 'Tenant identifier',
  tenant_name   STRING COMMENT 'Tenant legal name',
  industry      STRING COMMENT 'Tenant industry',
  credit_rating STRING COMMENT 'Tenant credit rating (AAA to B)',
  contact_name  STRING COMMENT 'Lease contact name (masked unless granite_pii_readers)'  MASK ${uc_schema}.mask_contact,
  contact_email STRING COMMENT 'Lease contact email (masked unless granite_pii_readers)' MASK ${uc_schema}.mask_contact,
  contact_phone STRING COMMENT 'Lease contact phone (masked unless granite_pii_readers)' MASK ${uc_schema}.mask_contact
)
COMMENT 'Tenant directory; contact columns are masked for everyone outside granite_pii_readers'
AS SELECT tenant_id, tenant_name, industry, credit_rating, contact_name, contact_email, contact_phone
FROM silver_tenant;

-- ── rollover_schedule: ABR at risk by expiry quarter ─────────────────────────

CREATE OR REFRESH MATERIALIZED VIEW rollover_schedule
COMMENT 'Annualized base rent and square feet expiring per quarter, by fund, property type and MSA'
WITH ROW FILTER ${uc_schema}.fund_row_filter ON (fund_id)
AS SELECT
  fund_id,
  property_type,
  msa,
  date_trunc('quarter', lease_end) AS expiry_quarter,
  COUNT(*)                         AS lease_count,
  SUM(annual_base_rent)            AS abr_at_risk,
  SUM(unit_sqft)                   AS sqft_at_risk
FROM rent_roll
GROUP BY ALL;

-- ── occupancy_monthly: leased vs. total square feet per property and month ───

CREATE OR REFRESH MATERIALIZED VIEW occupancy_monthly
COMMENT 'Monthly physical occupancy per property, derived from billed base rent (24 months of history)'
WITH ROW FILTER ${uc_schema}.fund_row_filter ON (fund_id)
AS WITH leased AS (
  SELECT
    cl.property_id,
    to_date(lc.charge_period, 'yyyy-MM') AS period_month,
    SUM(u.sqft)                          AS leased_sqft
  FROM silver_lease_charges lc
  JOIN silver_commlease cl ON lc.lease_id = cl.lease_id
  JOIN silver_unit u       ON cl.unit_id = u.unit_id
  WHERE lc.charge_type = 'Base Rent'
  GROUP BY ALL
),
total AS (
  SELECT property_id, SUM(sqft) AS total_sqft FROM silver_unit GROUP BY property_id
)
SELECT
  l.property_id,
  p.fund_id,
  p.property_type,
  p.msa,
  p.state,
  p.region,
  l.period_month,
  l.leased_sqft,
  t.total_sqft,
  l.leased_sqft / t.total_sqft AS occupancy_rate
FROM leased l
JOIN total t           ON l.property_id = t.property_id
JOIN property_h3 p     ON l.property_id = p.property_id;

-- ── lease_discrepancies: lease abstract vs. ERP mismatches ───────────────────

CREATE OR REFRESH MATERIALIZED VIEW lease_discrepancies
COMMENT 'Leases whose PDF terms disagree with the ERP (expiration date or monthly rent)'
AS SELECT
  le.lease_id,
  cl.property_id,
  le.tenant_name                               AS abstract_tenant,
  CAST(cl.lease_end AS DATE)                   AS erp_lease_end,
  le.lease_end                                 AS abstract_lease_end,
  cl.monthly_rent                              AS erp_monthly_rent,
  le.monthly_rent                              AS abstract_monthly_rent,
  CAST(cl.lease_end AS DATE) <> le.lease_end   AS expiration_mismatch,
  abs(cl.monthly_rent - le.monthly_rent) > 1   AS rent_mismatch,
  le.abstract_confidence
FROM lease_abstract le
JOIN silver_commlease cl ON le.lease_id = cl.lease_id
WHERE CAST(cl.lease_end AS DATE) <> le.lease_end
   OR abs(cl.monthly_rent - le.monthly_rent) > 1;

-- ── deal_abstract: extraction from offering memoranda and rent rolls ─────────

CREATE OR REFRESH MATERIALIZED VIEW deal_abstract
COMMENT 'Deal financials and in-place lease terms extracted from offering memoranda and rent rolls'
AS SELECT
  de.*
FROM silver_deal_extract de;

-- ── deal_lease_terms: one row per in-place lease listed in a deal document ──

CREATE OR REFRESH MATERIALIZED VIEW deal_lease_terms
COMMENT 'In-place leases extracted from deal offering memoranda (OM) and rent rolls (RentRoll): tenant, ABR, expiry, renewal options, co-tenancy'
AS SELECT
  de.deal_id,
  de.doc_type,
  t.tenant_name,
  t.abr,
  t.lease_end,
  t.renewal_options,
  t.has_co_tenancy,
  t.co_tenancy_terms
FROM silver_deal_extract de
LATERAL VIEW explode(de.tenant_list) x AS t;

-- ── deal_pipeline: deals with H3 and stage/financials ────────────────────────

CREATE OR REFRESH MATERIALIZED VIEW deal_pipeline
COMMENT 'Acquisition and disposition pipeline with H3 cells'
AS SELECT
  d.*,
  h3_longlatash3(d.lon, d.lat, 9)  AS h3_res9,
  h3_longlatash3(d.lon, d.lat, 7)  AS h3_res7
FROM silver_deal d;

-- ── h3_market_context: POIs within ~1 km (k-ring 3 at res 9) of each property

CREATE OR REFRESH MATERIALIZED VIEW h3_market_context
COMMENT 'Overture POI counts within ~1 km (H3 res-9 k-ring of 3) of each property; competitor_count matches the property type'
AS WITH ring AS (
  SELECT ph.property_id, ph.property_type, ph.h3_res9, explode(h3_kring(ph.h3_res9, 3)) AS neighbor_h3
  FROM property_h3 ph
)
SELECT
  r.property_id,
  r.property_type,
  r.h3_res9,
  COUNT(op.id)                                                   AS nearby_poi_count,
  COUNT(CASE WHEN op.poi_group = 'retail'            THEN op.id END) AS retail_count,
  COUNT(CASE WHEN op.poi_group = 'food_and_beverage' THEN op.id END) AS food_and_beverage_count,
  COUNT(CASE WHEN op.poi_group = 'office'            THEN op.id END) AS office_count,
  COUNT(CASE WHEN op.poi_group = 'industrial'        THEN op.id END) AS industrial_count,
  COUNT(CASE WHEN op.poi_group = 'amenity'           THEN op.id END) AS amenity_count,
  COUNT(CASE WHEN (r.property_type = 'Retail'     AND op.poi_group IN ('retail', 'food_and_beverage'))
               OR (r.property_type = 'Office'     AND op.poi_group = 'office')
               OR (r.property_type = 'Industrial' AND op.poi_group = 'industrial')
             THEN op.id END)                                     AS competitor_count
FROM ring r
LEFT JOIN silver_overture_places_h3 op ON op.h3_res9 = r.neighbor_h3
GROUP BY ALL;

-- ── property_neighborhood: exact polygon membership via H3 candidates ────────
-- h3_coverash3 fully covers each polygon with res-7 cells (unlike h3_polyfillash3, which can miss
-- boundary cells), the property's res-7 cell selects candidates, and st_covers makes the exact test.

CREATE OR REFRESH MATERIALIZED VIEW property_neighborhood
COMMENT 'Overture neighborhood, macrohood and locality containing each property (exact st_covers test)'
AS WITH cells AS (
  SELECT id, name_primary, subtype, geometry, explode(h3_coverash3(geometry, 7)) AS h3_res7
  FROM bronze_overture_division_areas
  WHERE subtype IN ('neighborhood', 'macrohood', 'locality')
),
matches AS (
  SELECT ph.property_id, c.subtype, c.name_primary
  FROM property_h3 ph
  JOIN cells c ON ph.h3_res7 = c.h3_res7
  WHERE st_covers(st_geomfromwkb(c.geometry), st_point(ph.lon, ph.lat))
)
SELECT
  ph.property_id,
  ph.msa,
  max(CASE WHEN m.subtype = 'neighborhood' THEN m.name_primary END) AS neighborhood,
  max(CASE WHEN m.subtype = 'macrohood'    THEN m.name_primary END) AS macrohood,
  max(CASE WHEN m.subtype = 'locality'     THEN m.name_primary END) AS locality
FROM property_h3 ph
LEFT JOIN matches m ON ph.property_id = m.property_id
GROUP BY ph.property_id, ph.msa;

-- ── property_360: one row per property for Lakebase serving and the app ──────
-- No row filter: synced tables need an unfiltered source. The app is the access boundary.

CREATE OR REFRESH MATERIALIZED VIEW property_360
COMMENT 'Property summary for operational serving (Lakebase): occupancy, ABR, WALT, rollover, H3 market context, neighborhood'
AS WITH leases AS (
  SELECT
    cl.property_id,
    COUNT(*)                                                         AS active_leases,
    SUM(cl.annual_base_rent)                                         AS abr,
    SUM(cl.annual_base_rent * months_between(CAST(cl.lease_end AS DATE), DATE'${as_of_date}'))
      / SUM(cl.annual_base_rent) / 12                                AS walt_years,
    SUM(cl.annual_base_rent) FILTER (WHERE CAST(cl.lease_end AS DATE) <= add_months(DATE'${as_of_date}', 24))
      / SUM(cl.annual_base_rent)                                     AS pct_abr_expiring_24m
  FROM silver_commlease cl
  WHERE cl.lease_status = 'Active'
  GROUP BY cl.property_id
),
occ AS (
  SELECT cl.property_id, SUM(u.sqft) AS leased_sqft
  FROM silver_commlease cl JOIN silver_unit u ON cl.unit_id = u.unit_id
  WHERE cl.lease_status = 'Active'
  GROUP BY cl.property_id
),
units AS (SELECT property_id, SUM(sqft) AS total_sqft FROM silver_unit GROUP BY property_id)
SELECT
  p.property_id, p.property_name, p.property_type, p.fund_id, p.address, p.city, p.state, p.msa, p.region,
  p.lat, p.lon, p.h3_res9, p.year_built, u.total_sqft,
  coalesce(o.leased_sqft, 0) / u.total_sqft AS occupancy_rate,
  coalesce(l.active_leases, 0)              AS active_leases,
  coalesce(l.abr, 0)                        AS abr,
  l.walt_years,
  l.pct_abr_expiring_24m,
  m.competitor_count,
  m.amenity_count,
  n.neighborhood,
  n.locality
FROM property_h3 p
JOIN units u                    ON p.property_id = u.property_id
LEFT JOIN leases l              ON p.property_id = l.property_id
LEFT JOIN occ o                 ON p.property_id = o.property_id
LEFT JOIN h3_market_context m   ON p.property_id = m.property_id
LEFT JOIN property_neighborhood n ON p.property_id = n.property_id;
