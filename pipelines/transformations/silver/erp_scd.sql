-- Silver: AUTO CDC from bronze CDC streams
-- SCD Type 1 latest-state dimensions keyed on each entity's primary key, plus SCD Type 2 lease history.

-- Fund
CREATE OR REFRESH STREAMING TABLE silver_fund;

CREATE FLOW silver_fund_cdc AS AUTO CDC INTO silver_fund
FROM STREAM(bronze_fund)
KEYS (fund_id)
APPLY AS DELETE WHEN header__operation = 'D'
SEQUENCE BY header__timestamp
COLUMNS * EXCEPT (header__operation, header__timestamp)
STORED AS SCD TYPE 1;

-- Property
CREATE OR REFRESH STREAMING TABLE silver_property;

CREATE FLOW silver_property_cdc AS AUTO CDC INTO silver_property
FROM STREAM(bronze_property)
KEYS (property_id)
APPLY AS DELETE WHEN header__operation = 'D'
SEQUENCE BY header__timestamp
COLUMNS * EXCEPT (header__operation, header__timestamp)
STORED AS SCD TYPE 1;

-- Unit
CREATE OR REFRESH STREAMING TABLE silver_unit;

CREATE FLOW silver_unit_cdc AS AUTO CDC INTO silver_unit
FROM STREAM(bronze_unit)
KEYS (unit_id)
APPLY AS DELETE WHEN header__operation = 'D'
SEQUENCE BY header__timestamp
COLUMNS * EXCEPT (header__operation, header__timestamp)
STORED AS SCD TYPE 1;

-- Tenant
CREATE OR REFRESH STREAMING TABLE silver_tenant;

CREATE FLOW silver_tenant_cdc AS AUTO CDC INTO silver_tenant
FROM STREAM(bronze_tenant)
KEYS (tenant_id)
APPLY AS DELETE WHEN header__operation = 'D'
SEQUENCE BY header__timestamp
COLUMNS * EXCEPT (header__operation, header__timestamp)
STORED AS SCD TYPE 1;

-- Commercial Lease
CREATE OR REFRESH STREAMING TABLE silver_commlease;

CREATE FLOW silver_commlease_cdc AS AUTO CDC INTO silver_commlease
FROM STREAM(bronze_commlease)
KEYS (lease_id)
APPLY AS DELETE WHEN header__operation = 'D'
SEQUENCE BY header__timestamp
COLUMNS * EXCEPT (header__operation, header__timestamp)
STORED AS SCD TYPE 1;

-- Commercial Lease history (SCD Type 2): every rent change and term update, with validity windows
CREATE OR REFRESH STREAMING TABLE silver_commlease_history
COMMENT 'Lease history from ERP CDC (SCD Type 2): one row per version, __START_AT / __END_AT validity';

CREATE FLOW silver_commlease_history_cdc AS AUTO CDC INTO silver_commlease_history
FROM STREAM(bronze_commlease)
KEYS (lease_id)
APPLY AS DELETE WHEN header__operation = 'D'
SEQUENCE BY header__timestamp
COLUMNS * EXCEPT (header__operation, header__timestamp)
STORED AS SCD TYPE 2;

-- Deal
CREATE OR REFRESH STREAMING TABLE silver_deal;

CREATE FLOW silver_deal_cdc AS AUTO CDC INTO silver_deal
FROM STREAM(bronze_deal)
KEYS (deal_id)
APPLY AS DELETE WHEN header__operation = 'D'
SEQUENCE BY header__timestamp
COLUMNS * EXCEPT (header__operation, header__timestamp)
STORED AS SCD TYPE 1;

-- Deal Comps
CREATE OR REFRESH STREAMING TABLE silver_deal_comps;

CREATE FLOW silver_deal_comps_cdc AS AUTO CDC INTO silver_deal_comps
FROM STREAM(bronze_deal_comps)
KEYS (comp_id)
APPLY AS DELETE WHEN header__operation = 'D'
SEQUENCE BY header__timestamp
COLUMNS * EXCEPT (header__operation, header__timestamp)
STORED AS SCD TYPE 1;
