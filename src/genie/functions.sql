-- Trusted H3 functions for the Genie space. ${uc_schema} is replaced by notebooks/04_semantic_layer.ipynb.
-- At H3 resolution 9, one ring step between neighboring cell centers is about 0.3 km,
-- so k_ring 3 is roughly 1 km and k_ring 7 roughly 2 km. Distances returned are great-circle km.

CREATE OR REPLACE FUNCTION ${uc_schema}.assets_near_deal(
  p_deal_id STRING COMMENT 'Deal identifier, for example GP-ACQ-014',
  k_ring    INT    DEFAULT 7 COMMENT 'H3 res-9 ring radius: 3 is about 1 km, 7 is about 2 km'
)
RETURNS TABLE (
  deal_id STRING, property_id STRING, property_name STRING, property_type STRING, msa STRING,
  distance_km DOUBLE, occupancy_rate DOUBLE, annual_base_rent DOUBLE
)
COMMENT 'Held Granite Peak assets near a pipeline deal (H3 k-ring candidates, great-circle distance), with current occupancy and ABR'
RETURN
  WITH d AS (SELECT * FROM ${uc_schema}.deal_pipeline WHERE deal_id = p_deal_id),
  cells AS (SELECT d.deal_id, d.lon, d.lat, explode(h3_kring(d.h3_res9, k_ring)) AS h3_res9 FROM d),
  latest AS (
    SELECT property_id, occupancy_rate FROM ${uc_schema}.occupancy_monthly
    WHERE period_month = (SELECT max(period_month) FROM ${uc_schema}.occupancy_monthly)
  ),
  abr AS (SELECT property_id, SUM(annual_base_rent) AS annual_base_rent FROM ${uc_schema}.rent_roll GROUP BY property_id)
  SELECT c.deal_id, p.property_id, p.property_name, p.property_type, p.msa,
         round(st_distancesphere(st_point(c.lon, c.lat), st_point(p.lon, p.lat)) / 1000, 2) AS distance_km,
         l.occupancy_rate, a.annual_base_rent
  FROM cells c
  JOIN ${uc_schema}.property_h3 p ON p.h3_res9 = c.h3_res9
  LEFT JOIN latest l ON l.property_id = p.property_id
  LEFT JOIN abr a    ON a.property_id = p.property_id;

CREATE OR REPLACE FUNCTION ${uc_schema}.assets_near(
  p_lon  DOUBLE COMMENT 'Longitude (WGS84), given before latitude',
  p_lat  DOUBLE COMMENT 'Latitude (WGS84)',
  k_ring INT    DEFAULT 7 COMMENT 'H3 res-9 ring radius: 3 is about 1 km, 7 is about 2 km'
)
RETURNS TABLE (
  property_id STRING, property_name STRING, property_type STRING, msa STRING, distance_km DOUBLE
)
COMMENT 'Granite Peak assets near a longitude/latitude point (H3 k-ring candidates, great-circle distance)'
RETURN
  SELECT p.property_id, p.property_name, p.property_type, p.msa,
         round(st_distancesphere(st_point(p_lon, p_lat), st_point(p.lon, p.lat)) / 1000, 2) AS distance_km
  FROM ${uc_schema}.property_h3 p
  WHERE array_contains(h3_kring(h3_longlatash3(p_lon, p_lat, 9), k_ring), p.h3_res9);

CREATE OR REPLACE FUNCTION ${uc_schema}.competitors_within(
  p_property_id STRING COMMENT 'Property identifier, for example GP-PROP-0001',
  k_ring        INT    DEFAULT 3 COMMENT 'H3 res-9 ring radius: 3 is about 1 km, 7 is about 2 km'
)
RETURNS TABLE (property_id STRING, poi_group STRING, poi_count BIGINT, is_competitor BOOLEAN)
COMMENT 'Overture POI counts by group around a property; is_competitor marks groups that compete with its property type'
RETURN
  WITH p AS (SELECT property_id, property_type, h3_res9 FROM ${uc_schema}.property_h3 WHERE property_id = p_property_id),
  ring AS (SELECT p.property_id, p.property_type, explode(h3_kring(p.h3_res9, k_ring)) AS h3_res9 FROM p)
  SELECT r.property_id, op.poi_group, COUNT(*) AS poi_count,
         (r.property_type = 'Retail' AND op.poi_group IN ('retail', 'food_and_beverage'))
      OR (r.property_type = 'Office' AND op.poi_group = 'office')
      OR (r.property_type = 'Industrial' AND op.poi_group = 'industrial') AS is_competitor
  FROM ring r
  JOIN ${uc_schema}.silver_overture_places_h3 op ON op.h3_res9 = r.h3_res9
  GROUP BY r.property_id, r.property_type, op.poi_group;
