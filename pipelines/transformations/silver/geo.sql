-- Silver: Overture places with H3 cells and a POI group used for competitor and amenity counts

CREATE OR REFRESH MATERIALIZED VIEW silver_overture_places_h3
COMMENT 'Overture Maps places (CDLA Permissive 2.0) with H3 res-9 cells and a POI group'
AS SELECT
  p.id,
  p.name_primary,
  p.category_primary,
  CASE
    WHEN p.category_primary RLIKE '_store$|^shopping|^department_store|^supermarket|^grocery|^pharmacy'
      THEN 'retail'
    WHEN p.category_primary RLIKE 'restaurant|eatery|coffee|cafe|bar$|bakery|fast_food'
      THEN 'food_and_beverage'
    WHEN p.category_primary RLIKE '^corporate_or_business_office|^professional_service|^financial_service|attorney|legal_service|^coworking'
      THEN 'office'
    WHEN p.category_primary RLIKE '^manufacturer|^supplier_or_distributor|warehouse|logistic|freight|shipping'
      THEN 'industrial'
    WHEN p.category_primary RLIKE '^park|gym|fitness|^hotel|^school|health_care|clinic'
      THEN 'amenity'
    ELSE 'other'
  END AS poi_group,
  p.confidence,
  ST_X(ST_GeomFromWKB(p.geometry)) AS lon,
  ST_Y(ST_GeomFromWKB(p.geometry)) AS lat,
  h3_longlatash3(ST_X(ST_GeomFromWKB(p.geometry)), ST_Y(ST_GeomFromWKB(p.geometry)), 9) AS h3_res9
FROM bronze_overture_places p
WHERE p.geometry IS NOT NULL;
