# scripts/

Headless alternatives to the notebook, for when a Colab Enterprise runtime is slow or
unavailable.

`load.sh` reaches the same end state as `notebooks/c_telehealth_01_load_explore.ipynb`—the same
five tables, with native `GEOGRAPHY` columns (`tract_geom`, `facility_geom`, `closure_geom`) and
leading-zero-safe 11-digit tract GEOIDs (`01` in Alabama, `06` in California), in `a4i_telehealth`
inside your project. Use the notebook if you can: Section 2 proves why pooling raw checkup rates
across states triggers Simpson's paradox and why `routine_checkup_within_1yr_pct` leaks `R^2 = 1.0`
into BigQuery ML. Use this script if you cannot.

## Running it

From the **root of the repo**, in Cloud Shell:

```bash
bash scripts/load.sh              # loads Mississippi (MS)—the default
bash scripts/load.sh AL           # Alabama (leading-zero FIPS 01)
bash scripts/load.sh CA           # California (leading-zero FIPS 06)
bash scripts/load.sh --list       # show every pre-staged state
bash scripts/load.sh --help       # usage
```

**It takes a two-letter state abbreviation (`MS`, `AL`, `GA`, `TX`, `CA`, `NY`).** Invoke it with
`bash` rather than `./scripts/load.sh` so it works regardless of whether the file's executable bit
survived how your copy of the repository was created.

If `A4I_SNAPSHOT_BUCKET` is configured in `.env` (or exported in your shell; see `.env.example`),
`load.sh` loads pre-filtered GeoParquet snapshots from Cloud Storage. Otherwise, it loads and
filters directly from the repository's `data/*.parquet` files using `bq`.

## It is safe to run more than once

Every table is fully replaced (`--replace`), never appended to. Canceling halfway through or
switching states on a second run overwrites the previous state's tables cleanly rather than mixing
states.

## What the verification block checks

- **Non-zero `checkup_gap_pct_pts` spread** across rural and urban comparator tracts, confirming
  your BigQuery ML model has a real within-state signal to learn.
- **Preserved 11-character `census_tract_geoid` strings** (`0` malformed rows, even in `AL` `01`
  and `CA` `06`).
- **Active organizational facilities, statutory safety-net clinics, and 10-year closures** ready
  for `ST_DISTANCE` feature engineering.
