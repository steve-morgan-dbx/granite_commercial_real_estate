-- Bronze: ERP CDC ingest via Auto Loader (Qlik Replicate-style JSONL files)
-- Each entity table lands in its own streaming table, filtered by filename prefix.

CREATE OR REFRESH STREAMING TABLE bronze_fund
AS SELECT * FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/erp_cdc/',
  format => 'json',
  pathGlobFilter => 'fund_*.jsonl'
));

CREATE OR REFRESH STREAMING TABLE bronze_property
AS SELECT * FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/erp_cdc/',
  format => 'json',
  pathGlobFilter => 'property_*.jsonl'
));

CREATE OR REFRESH STREAMING TABLE bronze_unit
AS SELECT * FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/erp_cdc/',
  format => 'json',
  pathGlobFilter => 'unit_*.jsonl'
));

CREATE OR REFRESH STREAMING TABLE bronze_tenant
AS SELECT * FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/erp_cdc/',
  format => 'json',
  pathGlobFilter => 'tenant_*.jsonl'
));

CREATE OR REFRESH STREAMING TABLE bronze_commlease
AS SELECT * FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/erp_cdc/',
  format => 'json',
  pathGlobFilter => 'commlease_*.jsonl'
));

CREATE OR REFRESH STREAMING TABLE bronze_lease_charges
AS SELECT * FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/erp_cdc/',
  format => 'json',
  pathGlobFilter => 'lease_charges_*.jsonl'
));

CREATE OR REFRESH STREAMING TABLE bronze_gl_actuals
AS SELECT * FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/erp_cdc/',
  format => 'json',
  pathGlobFilter => 'gl_actuals_*.jsonl'
));

CREATE OR REFRESH STREAMING TABLE bronze_deal
AS SELECT * FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/erp_cdc/',
  format => 'json',
  pathGlobFilter => 'deal_2*.jsonl'
));

CREATE OR REFRESH STREAMING TABLE bronze_deal_comps
AS SELECT * FROM STREAM(read_files(
  '/Volumes/smmorgan_catalog/granite_commercial_real_estate/landing/erp_cdc/',
  format => 'json',
  pathGlobFilter => 'deal_comps_*.jsonl'
));
