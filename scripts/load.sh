#!/usr/bin/env bash
#
# A4I 2026 - Digital Connectivity & Telehealth Access Equity
# Headless fallback for notebooks/c_telehealth_01_load_explore.ipynb
#
# Rebuilds the same five BigQuery tables the notebook produces, either from a
# pre-staged Cloud Storage snapshot (when A4I_SNAPSHOT_BUCKET is set in .env or
# the environment) or directly from the repo's data/*.parquet files via bq.
#
# Run it from the repo root in Cloud Shell (no chmod needed - invoke with bash):
#     bash scripts/load.sh                 # defaults to MS (Mississippi)
#     bash scripts/load.sh AL              # Alabama (leading-zero FIPS 01)
#     bash scripts/load.sh CA              # California (leading-zero FIPS 06)
#     bash scripts/load.sh --list          # show available states
#
# You still want the notebook if you can run it. Section 2 proves why pooling
# raw checkup rates across states produces Simpson's paradox and why leaving
# routine_checkup_within_1yr_pct in your feature list causes R^2 = 1.0 leakage.
# This script gets you the same tables without the teaching.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TABLES=(
  cdc_tract_health_utilization
  acs_income_and_device_ownership
  fcc_broadband_coverage_by_tract
  active_health_facilities_registry
  historical_facility_closures_10yr
)
REQUIRED=("${TABLES[@]}")
SCOPE_ORDER=(MS AL GA TX CA NY)

declare -A STATE_NAMES=(
  [MS]="Mississippi (FIPS 28, 5 rural + 1 urban comparator) - notebook default"
  [AL]="Alabama (FIPS 01 - leading-zero state)"
  [GA]="Georgia (FIPS 13)"
  [TX]="Texas (FIPS 48)"
  [CA]="California (FIPS 06 - leading-zero state)"
  [NY]="New York (FIPS 36)"
)

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
fail() {
  printf '\n\033[1mERROR:\033[0m %s\n\n%s\n\n' "$*" \
    "This script is safe to run again - every table load replaces whatever was there." >&2
  exit 1
}

on_interrupt() {
  printf '\n\n\033[1mInterrupted.\033[0m Nothing is broken.\n'
  printf 'Every load replaces the whole table, so run this script again:\n'
  printf '    bash scripts/load.sh %s\n\n' "${STATE:-<STATE>}"
  exit 130
}
trap on_interrupt INT TERM

load_dotenv() {
  local env_file="${REPO_ROOT}/.env" line_no=0 line key val
  [[ -f "${env_file}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line_no=$((line_no + 1))
    [[ "${line_no}" -le 200 ]] || fail ".env exceeds 200 lines."
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    if [[ "${line}" =~ ^(A4I_[A-Z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      val="${val%$'\r'}"
      if [[ "${val}" =~ ^\"(.*)\"$ || "${val}" =~ ^\'(.*)\'$ ]]; then
        val="${BASH_REMATCH[1]}"
      fi
      if [[ -z "${!key:-}" ]]; then
        declare -gx "${key}=${val}"
      fi
    fi
  done < "${env_file}"
}

run_timed() {
  [[ $# -ge 1 ]] || fail "Internal error: run_timed called without command."
  [[ "${CMD_TIMEOUT_SEC}" =~ ^[1-9][0-9]{0,3}$ ]] \
    || fail "Invalid A4I_CMD_TIMEOUT_SEC='${CMD_TIMEOUT_SEC}' (expected 1..9999)."
  if command -v timeout >/dev/null 2>&1; then
    timeout "${CMD_TIMEOUT_SEC}s" "$@"
  else
    "$@"
  fi
}

validate_config() {
  SNAPSHOT_BUCKET="${A4I_SNAPSHOT_BUCKET:-}"
  SNAPSHOT_BUCKET="${SNAPSHOT_BUCKET#gs://}"
  SNAPSHOT_BUCKET="${SNAPSHOT_BUCKET%/}"
  SNAPSHOT_PREFIX="${A4I_SNAPSHOT_PREFIX:-a4i-2026/challenge-telehealth}"
  SNAPSHOT_PREFIX="${SNAPSHOT_PREFIX#/}"
  SNAPSHOT_PREFIX="${SNAPSHOT_PREFIX%/}"
  DATASET="${A4I_DATASET:-a4i_telehealth}"
  LOCATION="${A4I_LOCATION:-US}"
  CMD_TIMEOUT_SEC="${A4I_CMD_TIMEOUT_SEC:-180}"

  [[ "${CMD_TIMEOUT_SEC}" =~ ^[1-9][0-9]{0,3}$ ]] \
    || fail "Invalid A4I_CMD_TIMEOUT_SEC='${CMD_TIMEOUT_SEC}' (expected 1..9999)."
  [[ "${DATASET}" =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,1023}$ ]] \
    || fail "Invalid dataset identifier '${DATASET}'."
  [[ "${LOCATION}" =~ ^[A-Za-z0-9-]+$ ]] \
    || fail "Invalid BigQuery location '${LOCATION}'."
  if [[ -n "${SNAPSHOT_BUCKET}" ]] && [[ ! "${SNAPSHOT_BUCKET}" =~ ^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$ ]]; then
    fail "Invalid A4I_SNAPSHOT_BUCKET='${SNAPSHOT_BUCKET}'."
  fi
}

list_states() {
  bold "States available for Digital & Telehealth Access Equity"
  local found=0 code label
  if [[ -n "${SNAPSHOT_BUCKET}" ]]; then
    local base_uri="gs://${SNAPSHOT_BUCKET}/${SNAPSHOT_PREFIX}"
    while read -r code; do
      [[ -z "${code}" || "${code}" == "starter" ]] && continue
      found=1
      label="${STATE_NAMES[${code}]:-(in snapshot bucket)}"
      printf '  %-6s %s\n' "${code}" "${label}"
    done < <(run_timed gcloud storage ls "${base_uri}/" 2>/dev/null | sed 's|.*/\([^/]*\)/$|\1|')
    [[ "${found}" -eq 1 ]] || fail "Could not list ${base_uri}/. Check network access and authentication."
  else
    for code in "${SCOPE_ORDER[@]}"; do
      printf '  %-6s %s\n' "${code}" "${STATE_NAMES[${code}]}"
    done
  fi
  echo
  echo "Usage: bash scripts/load.sh <STATE>"
}

resolve_state() {
  local raw="${1:-MS}"
  if [[ "${raw}" == "--list" || "${raw}" == "-l" ]]; then
    list_states
    exit 0
  fi
  if [[ "${raw}" == "--help" || "${raw}" == "-h" ]]; then
    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
  fi
  [[ "${raw}" != *".."* && "${raw}" != *"/"* ]] \
    || fail "Invalid state argument '${raw}'."
  STATE="$(printf '%s' "${raw}" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')"
  [[ "${STATE}" =~ ^[A-Z]{2}$ ]] \
    || fail "'${raw}' is not a two-letter state abbreviation. Try: bash scripts/load.sh MS"
  STATE_LABEL="${STATE_NAMES[${STATE}]:-${STATE}}"
  if [[ -n "${SNAPSHOT_BUCKET}" ]]; then
    SRC="gs://${SNAPSHOT_BUCKET}/${SNAPSHOT_PREFIX}/${STATE}"
  else
    [[ -n "${STATE_NAMES[${STATE}]:-}" ]] || {
      echo
      bold "State '${STATE}' is not in the six pre-staged starter states."
      echo
      list_states
      exit 1
    }
    SRC="${REPO_ROOT}/data (filtered to ${STATE})"
  fi
}

preflight_checks() {
  bold "A4I Telehealth Equity - loading data for: ${STATE} — ${STATE_LABEL}"
  echo
  command -v bq     >/dev/null 2>&1 || fail "'bq' not found. Run this in Cloud Shell."
  command -v gcloud >/dev/null 2>&1 || fail "'gcloud' not found. Run this in Cloud Shell."

  PROJECT_ID="$(run_timed gcloud config get-value project 2>/dev/null || true)"
  [[ -n "${PROJECT_ID}" && "${PROJECT_ID}" != "(unset)" ]] \
    || fail "No project set. Run: gcloud config set project YOUR_PROJECT_ID"
  [[ "${PROJECT_ID}" =~ ^[a-z][a-z0-9.:-]{4,60}$ ]] \
    || fail "Invalid GCP project ID '${PROJECT_ID}'."

  info "Project : ${PROJECT_ID}"
  info "State   : ${STATE}"
  info "Source  : ${SRC}"
  info "Dataset : ${DATASET} (${LOCATION})"
  echo

  if [[ -n "${SNAPSHOT_BUCKET}" ]]; then
    if ! run_timed gcloud storage ls "${SRC}/" >/dev/null 2>&1; then
      echo
      bold "No snapshot found for '${STATE}'."
      echo
      list_states
      exit 1
    fi
  else
    local tbl
    for tbl in "${REQUIRED[@]}"; do
      [[ -f "${REPO_ROOT}/data/${tbl}.parquet" ]] \
        || fail "Missing ${REPO_ROOT}/data/${tbl}.parquet. Run from the cloned repo root or set A4I_SNAPSHOT_BUCKET."
    done
  fi
}

ensure_dataset() {
  bold "1/3  Creating dataset"
  if run_timed bq --project_id="${PROJECT_ID}" show --dataset --format=none \
       "${PROJECT_ID}:${DATASET}" >/dev/null 2>&1; then
    info "${DATASET} already exists - reusing it"
    local existing_loc
    existing_loc="$(run_timed bq --project_id="${PROJECT_ID}" --format=json show --dataset \
                      "${PROJECT_ID}:${DATASET}" 2>/dev/null \
                    | tr ',' '\n' | grep -i '"location"' | head -1 \
                    | sed 's/.*: *"\([^"]*\)".*/\1/' || true)"
    if [[ -n "${existing_loc}" && "${existing_loc^^}" != "${LOCATION^^}" ]]; then
      fail "Dataset ${DATASET} already exists in '${existing_loc}', but this script loads into
       '${LOCATION}'. BigQuery cannot load across regions. Either delete the dataset
       (bq rm -r -d ${DATASET}) or set A4I_LOCATION to match."
    fi
  else
    local mk_out
    if mk_out="$(run_timed bq --project_id="${PROJECT_ID}" --location="${LOCATION}" \
                   mk --dataset "${PROJECT_ID}:${DATASET}" 2>&1)"; then
      info "created ${DATASET}"
    elif grep -qi "already exists" <<<"${mk_out}"; then
      info "${DATASET} already exists - reusing it"
    else
      fail "Could not create dataset ${DATASET}: ${mk_out}"
    fi
  fi
  echo
}

build_local_filter_sql() {
  local table="$1"
  local fq_dest="\`${PROJECT_ID}.${DATASET}.${table}\`"
  local fq_raw="\`${PROJECT_ID}.${DATASET}._raw_${table}\`"
  case "${table}" in
    cdc_tract_health_utilization)
      printf 'CREATE OR REPLACE TABLE %s AS SELECT * REPLACE (LPAD(census_tract_geoid, 11, '\''0'\'') AS census_tract_geoid) FROM %s WHERE state_code = '\''%s'\''' \
        "${fq_dest}" "${fq_raw}" "${STATE}"
      ;;
    acs_income_and_device_ownership|fcc_broadband_coverage_by_tract)
      printf 'CREATE OR REPLACE TABLE %s AS SELECT * REPLACE (LPAD(census_tract_geoid, 11, '\''0'\'') AS census_tract_geoid, LPAD(county_fips, 5, '\''0'\'') AS county_fips) FROM %s WHERE state_code = '\''%s'\''' \
        "${fq_dest}" "${fq_raw}" "${STATE}"
      ;;
    active_health_facilities_registry)
      printf 'CREATE OR REPLACE TABLE %s AS SELECT * REPLACE (LPAD(facility_npi, 10, '\''0'\'') AS facility_npi, LPAD(zip_code, 5, '\''0'\'') AS zip_code) FROM %s WHERE state_code = '\''%s'\''' \
        "${fq_dest}" "${fq_raw}" "${STATE}"
      ;;
    historical_facility_closures_10yr)
      printf 'CREATE OR REPLACE TABLE %s AS SELECT * REPLACE (LPAD(npi, 10, '\''0'\'') AS npi) FROM %s WHERE state_code = '\''%s'\''' \
        "${fq_dest}" "${fq_raw}" "${STATE}"
      ;;
    *)
      printf 'CREATE OR REPLACE TABLE %s AS SELECT * FROM %s WHERE state_code = '\''%s'\''' \
        "${fq_dest}" "${fq_raw}" "${STATE}"
      ;;
  esac
}

load_all_tables() {
  bold "2/3  Loading tables"
  local table uri sql
  for table in "${TABLES[@]}"; do
    info "loading ${table}..."
    if [[ -n "${SNAPSHOT_BUCKET}" ]]; then
      uri="${SRC}/${table}/data.parquet"
      if ! run_timed gcloud storage ls "${uri}" >/dev/null 2>&1; then
        uri="${SRC}/${table}/*.parquet"
        run_timed gcloud storage ls "${SRC}/${table}/" >/dev/null 2>&1 \
          || fail "Missing ${SRC}/${table}/. The snapshot for '${STATE}' looks incomplete - tell a coach."
      fi
      run_timed bq --project_id="${PROJECT_ID}" --location="${LOCATION}" load \
        --source_format=PARQUET --replace "${DATASET}.${table}" "${uri}" >/dev/null
    else
      run_timed bq --project_id="${PROJECT_ID}" --location="${LOCATION}" load \
        --source_format=PARQUET --replace \
        "${DATASET}._raw_${table}" "${REPO_ROOT}/data/${table}.parquet" >/dev/null
      sql="$(build_local_filter_sql "${table}")"
      run_timed bq --project_id="${PROJECT_ID}" --location="${LOCATION}" query \
        --use_legacy_sql=false --format=none "${sql}" >/dev/null
      run_timed bq --project_id="${PROJECT_ID}" rm -f -t \
        "${PROJECT_ID}:${DATASET}._raw_${table}" >/dev/null
    fi
    info "  done"
  done
  echo
}

verify_tables() {
  bold "3/3  Verifying"
  FAILED=0
  local table rows
  for table in "${TABLES[@]}"; do
    rows="$(run_timed bq --project_id="${PROJECT_ID}" --location="${LOCATION}" \
              query --use_legacy_sql=false --format=csv \
              "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.${table}\`" \
            | tail -n 1)"
    if [[ "${rows}" == "0" ]]; then
      printf '  %-38s %s\n' "${table}" "0 rows  <-- EMPTY"
      FAILED=1
    else
      printf '  %-38s %s rows\n' "${table}" "${rows}"
    fi
  done
  echo
}

verify_challenge_signals() {
  bold "Does this state support the challenge?"
  local tracts rural_tracts gap_spread facilities safety_net closures bad_geoid
  read -r tracts rural_tracts gap_spread facilities safety_net closures bad_geoid <<<"$(
    run_timed bq --project_id="${PROJECT_ID}" --location="${LOCATION}" \
      query --use_legacy_sql=false --format=csv \
      "SELECT
         (SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.cdc_tract_health_utilization\`),
         (SELECT IFNULL(COUNTIF(rural_urban_context = 'Rural'), 0)
            FROM \`${PROJECT_ID}.${DATASET}.fcc_broadband_coverage_by_tract\`),
         (SELECT IFNULL(ROUND(MAX(checkup_gap_pct_pts) - MIN(checkup_gap_pct_pts), 1), 0)
            FROM \`${PROJECT_ID}.${DATASET}.cdc_tract_health_utilization\`),
         (SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.active_health_facilities_registry\`),
         (SELECT IFNULL(COUNTIF(is_statutory_safety_net_clinic), 0)
            FROM \`${PROJECT_ID}.${DATASET}.active_health_facilities_registry\`),
         (SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.historical_facility_closures_10yr\`),
         (SELECT IFNULL(COUNTIF(LENGTH(census_tract_geoid) != 11), 0)
            FROM \`${PROJECT_ID}.${DATASET}.acs_income_and_device_ownership\`)" \
    | tail -n 1 | tr ',' ' '
  )"

  printf '  %-46s %s (%s rural)\n' "census tracts"                       "${tracts}" "${rural_tracts}"
  printf '  %-46s %s pct pts\n'    "checkup_gap_pct_pts spread (max-min)" "${gap_spread}"
  printf '  %-46s %s (%s safety-net)\n' "active organizational facilities" "${facilities}" "${safety_net}"
  printf '  %-46s %s\n'            "10-year facility closures"           "${closures}"
  printf '  %-46s %s\n'            "tracts with malformed GEOID (!=11)"  "${bad_geoid}"
  echo

  if [[ "${bad_geoid}" != "0" || "${rural_tracts}" == "0" || "${gap_spread}" == "0" || "${gap_spread}" == "0.0" ]]; then
    FAILED=1
    info "  <-- Broken tract GEOIDs or zero checkup_gap_pct_pts spread."
  fi

  if [[ "${FAILED}" -eq 1 ]]; then
    fail "One or more required tables loaded empty or failed integrity checks. Tell a coach."
  fi
}

print_ready_footer() {
  bold "Ready."
  echo
  echo "  Your tables are in ${PROJECT_ID}.${DATASET}"
  echo "  Safe to re-run at any time - each load replaces the whole table."
  echo
  echo "  THREE TRAPS THAT COST TEAMS CREDIT IF SKIPPED:"
  echo "    1. TARGET LEAKAGE: predict checkup_gap_pct_pts, and NEVER include"
  echo "       routine_checkup_within_1yr_pct or state_mean_checkup_pct as features"
  echo "       (they define the label algebraically -> R^2 = 1.0 leakage)."
  echo "    2. COLLINEARITY: unserved_bsl_under_25_3_count equals satellite_only_bsl_count"
  echo "       in the [Modeled] FCC table - include one, not both."
  echo "    3. EQUITY AUDIT: exclude audit_* shares from CREATE MODEL features; join"
  echo "       them after prediction to audit who your top-priority tracts serve."
  echo
  echo "  Next: train your BigQuery ML model (CREATE MODEL ... ENABLE_GLOBAL_EXPLAIN=TRUE)"
  echo "  and call ML.EXPLAIN_PREDICT from your agent. See Section 13 of"
  echo "  notebooks/c_telehealth_01_load_explore.ipynb."
  echo
}

load_dotenv
validate_config
resolve_state "${1:-MS}"
preflight_checks
ensure_dataset
load_all_tables
verify_tables
verify_challenge_signals
print_ready_footer
