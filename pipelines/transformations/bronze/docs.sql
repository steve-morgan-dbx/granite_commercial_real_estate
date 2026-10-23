-- Bronze: lease and deal PDF binary ingest via Auto Loader
-- ${landing_root} is set in the pipeline configuration (see resources/pipeline.yml).

CREATE OR REFRESH STREAMING TABLE bronze_lease_docs
AS SELECT
  path,
  content,
  modificationTime AS modification_time
FROM STREAM(read_files(
  '${landing_root}/docs/leases/',
  format => 'binaryFile'
));

CREATE OR REFRESH STREAMING TABLE bronze_deal_docs
AS SELECT
  path,
  content,
  modificationTime AS modification_time
FROM STREAM(read_files(
  '${landing_root}/docs/deals/',
  format => 'binaryFile'
));
