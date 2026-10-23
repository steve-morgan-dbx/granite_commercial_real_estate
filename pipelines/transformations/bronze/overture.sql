-- Bronze: Overture Maps open data (parquet) via Auto Loader
-- ${landing_root} is set in the pipeline configuration (see resources/pipeline.yml).

CREATE OR REFRESH STREAMING TABLE bronze_overture_places
AS SELECT
  id,
  geometry,
  names.primary AS name_primary,
  basic_category AS category_primary,
  confidence,
  bbox
FROM STREAM(read_files(
  '${landing_root}/overture/places/',
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
  '${landing_root}/overture/buildings/',
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
  '${landing_root}/overture/divisions/',
  format => 'parquet'
));

CREATE OR REFRESH STREAMING TABLE bronze_overture_division_areas
COMMENT 'Overture division_area polygons (neighborhood, macrohood, locality)'
AS SELECT
  id,
  geometry,
  names.primary AS name_primary,
  subtype,
  region,
  bbox
FROM STREAM(read_files(
  '${landing_root}/overture/division_areas/',
  format => 'parquet'
));
