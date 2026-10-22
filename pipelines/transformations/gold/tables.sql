-- Gold layer: portfolio-facing materialized views

-- ── property_h3: properties with H3 indices ──────────────────────────────────

CREATE OR REFRESH MATERIALIZED VIEW property_h3 AS
SELECT
  p.*,
  h3_longlatash3(p.lon, p.lat, 9)  AS h3_res9,
  h3_longlatash3(p.lon, p.lat, 7)  AS h3_res7
FROM silver_property p;

-- ── rent_roll: master lease view with has_abstract flag ──────────────────────

CREATE OR REFRESH MATERIALIZED VIEW rent_roll
CLUSTER BY (fund_id, property_id)
AS
SELECT
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
  u.unit_number,
  u.sqft         AS unit_sqft,
  t.tenant_name,
  t.industry,
  t.credit_rating,
  cl.lease_start,
  cl.lease_end,
  cl.monthly_rent,
  cl.annual_base_rent,
  cl.escalation_type,
  cl.renewal_option_count,
  cl.has_co_tenancy,
  cl.has_termination_right,
  cl.termination_right_date,
  cl.has_exclusive_use,
  CASE WHEN le.lease_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_abstract
FROM silver_commlease cl
JOIN silver_property p ON cl.property_id = p.property_id
JOIN silver_unit u     ON cl.unit_id = u.unit_id
JOIN silver_tenant t   ON cl.tenant_id = t.tenant_id
LEFT JOIN silver_lease_extract le ON cl.lease_id = le.lease_id;

-- ── rollover_schedule: ABR at risk by expiry quarter ─────────────────────────

CREATE OR REFRESH MATERIALIZED VIEW rollover_schedule AS
SELECT
  fund_id,
  property_type,
  msa,
  date_trunc('quarter', lease_end) AS expiry_quarter,
  COUNT(*)                         AS lease_count,
  SUM(annual_base_rent)            AS abr_at_risk,
  SUM(unit_sqft)                   AS sqft_at_risk
FROM rent_roll
GROUP BY ALL;

-- ── lease_abstract: extraction results (corrections from Lakebase added later) ─

CREATE OR REFRESH MATERIALIZED VIEW lease_abstract AS
SELECT
  le.*
  -- When Lakebase abstract_review is set up, add:
  -- COALESCE(ar.corrected_lease_end, le.lease_end) AS lease_end, etc.
FROM silver_lease_extract le;

-- ── deal_abstract: extraction from offering memoranda and rent rolls ─────────

CREATE OR REFRESH MATERIALIZED VIEW deal_abstract AS
SELECT
  de.*
FROM silver_deal_extract de;

-- ── deal_pipeline: deals with H3 and stage/financials ────────────────────────

CREATE OR REFRESH MATERIALIZED VIEW deal_pipeline AS
SELECT
  d.*,
  h3_longlatash3(d.lon, d.lat, 9)  AS h3_res9,
  h3_longlatash3(d.lon, d.lat, 7)  AS h3_res7
FROM silver_deal d;

-- ── lease_discrepancies: lease abstract vs ERP mismatches ────────────────────

CREATE OR REFRESH MATERIALIZED VIEW lease_discrepancies AS
SELECT
  le.lease_id,
  le.tenant_name        AS abstract_tenant,
  cl.lease_end          AS erp_lease_end,
  le.lease_end          AS abstract_lease_end,
  cl.monthly_rent       AS erp_monthly_rent,
  le.monthly_rent       AS abstract_monthly_rent,
  CASE
    WHEN cl.lease_end <> le.lease_end THEN TRUE
    ELSE FALSE
  END AS expiration_mismatch,
  CASE
    WHEN ABS(cl.monthly_rent - le.monthly_rent) > 50 THEN TRUE
    ELSE FALSE
  END AS rent_mismatch
FROM silver_lease_extract le
JOIN silver_commlease cl ON le.lease_id = cl.lease_id
WHERE cl.lease_end <> le.lease_end
   OR ABS(cl.monthly_rent - le.monthly_rent) > 50;

-- ── h3_market_context: POI density around each property hex ──────────────────

CREATE OR REFRESH MATERIALIZED VIEW silver_overture_places_h3 AS
SELECT
  p.id,
  p.name_primary,
  p.category_primary,
  p.confidence,
  ST_X(ST_GeomFromWKB(p.geometry)) AS lon,
  ST_Y(ST_GeomFromWKB(p.geometry)) AS lat,
  h3_longlatash3(
    ST_X(ST_GeomFromWKB(p.geometry)),
    ST_Y(ST_GeomFromWKB(p.geometry)),
    9
  ) AS h3_res9
FROM bronze_overture_places p;

CREATE OR REFRESH MATERIALIZED VIEW h3_market_context AS
SELECT
  ph.property_id,
  ph.h3_res9,
  COUNT(DISTINCT op.id) AS nearby_poi_count,
  COUNT(DISTINCT CASE WHEN op.category_primary LIKE '%restaurant%' THEN op.id END) AS restaurant_count,
  COUNT(DISTINCT CASE WHEN op.category_primary LIKE '%retail%'     THEN op.id END) AS retail_count,
  COUNT(DISTINCT CASE WHEN op.category_primary LIKE '%office%'     THEN op.id END) AS office_count,
  COUNT(DISTINCT CASE WHEN op.category_primary LIKE '%hotel%'      THEN op.id END) AS hotel_count
FROM property_h3 ph
CROSS JOIN LATERAL EXPLODE(h3_kring(ph.h3_res9, 3)) AS ring(neighbor_h3)
LEFT JOIN silver_overture_places_h3 op ON op.h3_res9 = ring.neighbor_h3
GROUP BY ph.property_id, ph.h3_res9;

-- ── renewal_scores: placeholder for ML model output ──────────────────────────

CREATE OR REFRESH MATERIALIZED VIEW renewal_scores AS
SELECT
  cl.lease_id,
  cl.tenant_id,
  cl.property_id,
  cl.annual_base_rent,
  cl.lease_end,
  CAST(NULL AS DOUBLE)  AS renewal_probability,
  CAST(NULL AS DOUBLE)  AS expected_vacancy_loss
FROM silver_commlease cl;
