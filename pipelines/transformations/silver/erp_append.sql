-- Silver: append-only ERP tables (no CDC merge needed)

CREATE OR REFRESH STREAMING TABLE silver_lease_charges
AS SELECT
  charge_id,
  lease_id,
  charge_type,
  charge_period,
  amount,
  paid,
  header__timestamp AS ingested_at
FROM STREAM(bronze_lease_charges);

CREATE OR REFRESH STREAMING TABLE silver_gl_actuals
AS SELECT
  gl_id,
  property_id,
  period,
  revenue,
  operating_expense,
  noi,
  header__timestamp AS ingested_at
FROM STREAM(bronze_gl_actuals);
