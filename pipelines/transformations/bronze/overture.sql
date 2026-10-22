-- Bronze: Overture Maps open data (parquet) via Auto Loader

CREATE OR REFRESH STREAMING TABLE bronze_overture_places
AS SELECT
  id,
  geometry,
  names.primary AS name_primary,
  basic_category AS category_primary,
  confidence,
  bbox
FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/overture/places/',
  format => 'parquet'
));

CREATE OR REFRESH STREAMING TABLE bronze_overture_buildings
AS SELECT
  id,
  geometry,
  names.primary AS name_primary,
  height,
  num_floors,
  subtype,
  class,
  bbox
FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/overture/buildings/',
  format => 'parquet'
));

CREATE OR REFRESH STREAMING TABLE bronze_overture_divisions
AS SELECT
  id,
  geometry,
  names.primary AS name_primary,
  subtype,
  bbox
FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/overture/divisions/',
  format => 'parquet'
));
