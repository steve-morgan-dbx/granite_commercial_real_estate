-- Bronze: lease and deal PDF binary ingest via Auto Loader

CREATE OR REFRESH STREAMING TABLE bronze_lease_docs
AS SELECT
  path,
  content,
  modificationTime AS modification_time
FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/docs/leases/',
  format => 'binaryFile'
));

CREATE OR REFRESH STREAMING TABLE bronze_deal_docs
AS SELECT
  path,
  content,
  modificationTime AS modification_time
FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/docs/deals/',
  format => 'binaryFile'
));
