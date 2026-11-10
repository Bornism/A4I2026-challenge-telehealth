# data/

Pre-staged GeoParquet starter tables covering six states (`MS`, `AL`, `GA`, `TX`, `CA`, and `NY`), pairing five rural high-need counties with one urban comparator county per state. When `A4I_SNAPSHOT_BUCKET` is unset, both [`notebooks/c_telehealth_01_load_explore.ipynb`](../notebooks/c_telehealth_01_load_explore.ipynb) and [`scripts/load.sh`](../scripts/load.sh) filter and load your chosen state directly from these five files into `a4i_telehealth` inside your Google Cloud project.

**Read the `data_provenance` column in every table.** You should not trust modeled data you cannot inspect, and neither should a judge.

## Files in this folder

### `cdc_tract_health_utilization.parquet` (428 rows across 6 states)

- **Provenance:** **100% real empirical public data.** Centers for Disease Control and Prevention (CDC) PLACES census-tract estimates (`data.cdc.gov` dataset `cwsq-ngmh`: `CHECKUP`, `ACCESS2`, `DIABETES`, `BPHIGH`, `DISABILITY`). CDC PLACES has no "preventable missed care" measure, so `checkup_gap_pct_pts` measures each tract's empirical shortfall against its own state baseline (`state_mean_checkup_pct - routine_checkup_within_1yr_pct`).
- **License:** US Government Work (public domain).
- **Leakage rule:** Never include `routine_checkup_within_1yr_pct` or `state_mean_checkup_pct` as training features when predicting `checkup_gap_pct_pts`, because they define the target algebraically (`R^2 = 1.0` leakage).

### `acs_income_and_device_ownership.parquet` (428 rows)

- **Provenance:** **Real public data.** US Census Bureau American Community Survey (ACS) 5-Year household internet subscriptions, cellular-only households, no-computing-device counts, zero-vehicle households, poverty rates, TIGER/Line polygons (`tract_geom`), and five `audit_*` demographic share columns.
- **Important rule:** Exclude all `audit_*` columns from `CREATE MODEL` training features. Join them strictly after generating predictions for your post-output Equity Audit.

### `fcc_broadband_coverage_by_tract.parquet` (428 rows)

- **Provenance:** **Modeled from public benchmarks.** Census-tract Broadband Serviceable Location (BSL) tier counts calibrated to Federal Communications Commission (FCC) Broadband Data Collection (BDC) rural/urban availability distributions and ACS internet subscription baselines.
- **Collinearity note:** `unserved_bsl_under_25_3_count` and `satellite_only_bsl_count` carry identical counts in this modeled table. Include one in your feature view, not both.

### `active_health_facilities_registry.parquet` (539 rows)

- **Provenance:** **Real public organizational records only.** Active Type-2 organizational facilities (`entity_type_code = 2`, zero individual clinicians) from the CMS National Plan and Provider Enumeration System (NPPES), enriched with HRSA Health Professional Shortage Area (HPSA) primary-care scores.

### `historical_facility_closures_10yr.parquet` (38 rows)

- **Provenance:** **Real public organizational records only.** Documented rural hospital closures from the UNC Cecil G. Sheps Center and deactivated Type-2 organizational clinics from CMS NPPES (2016 through 2025).
