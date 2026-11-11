# Digital Connectivity & Telehealth Access Equity ("The Offline Community")

**Agents for Impact 2026**

---

## Why this one matters

When a rural hospital or safety-net clinic closes its doors, the press release almost always promises the same thing: virtual care will bridge the gap. Across rural America, nearly two hundred hospitals have shut down or ended inpatient care over the past two decades. In the communities left behind, moving routine preventive care onto a video link only helps households that have a broadband line, a screen to hold the visit on, or a working car when the clinician says *"come in tomorrow."*

State broadband offices and regional rural-health planners know "the offline community" exists in the abstract. What they rarely have in one place is an honest empirical measure of preventive-care shortfalls for *this census tract*, clear attribution showing which specific barrier drives the gap here versus ten miles up the highway, and a planning tool that answers when a grant budget shifts at 4pm on a Thursday.

This is an **intervention-matching problem under a fixed budget**. Laying fiber to unserved locations, lending cellular-enabled tablets to households with LTE coverage but no computer, placing telehealth kiosks in county libraries, and dispatching a mobile clinic van solve four completely different barriers. Spend tablet money in a dead zone with zero cellular or broadband signal, and you mail screens to households that cannot connect them.

**Your job today is to build the planning assistant that predicts neighborhood checkup shortfalls, explains why each tract is falling behind, and matches the right intervention before grant dollars are misallocated.**

You will build it for **one state**, not for everywhere. Which of the six states you choose is your team's first real decision a few sections down.

---

## How to read this

**This is a reference for your whole afternoon, not something to read end to end right now.** Here is what each lane needs in the first fifteen minutes.

| If you are... | Read now | Come back for |
|---|---|---|
| **Everyone, together** | [The four things](#the-four-things-youre-working-with) · [Three tracks](#three-tracks-one-architecture) · [What you're building](#what-youre-building) · [Now pick your state](#now-pick-your-state) | Agree on these before anyone opens a keyboard |
| **Team lead** | [Step 0](#step-0-organize-your-team) · [How you'll be judged](#how-youll-be-judged) | [Going further](#going-further) (read it *before* writing code, not right before the demo) |
| **Data lane** | [Step 4, load the data](#step-4-load-the-data) · [What you'll have](#what-youll-have) | [The data, and why we chose it](#the-data-and-why-we-chose-it) · Section 13 of the notebook |
| **Agent lane** | [What you're building](#what-youre-building) · [The technology](#the-technology-youll-use) | [`agent/README.md`](agent/README.md) · [Questions that need more than we gave you](#questions-that-need-more-than-we-gave-you) |
| **Front end lane** | [Front end lane](#front-end-lane-2-people) | [Your output artifact](#your-output-artifact-the-intervention-allocation-plan) |
| **Story lane** | [Your output artifact](#your-output-artifact-the-intervention-allocation-plan) | [The data](#the-data-and-why-we-chose-it) (know what is empirical vs. modeled, because judges check) |

**Three things everybody should know by the end of hour one**, whatever lane you are in:

1. **CDC PLACES has no "preventable missed care" measure.** Instead, `cdc_tract_health_utilization` uses **100% real empirical CDC PLACES** routine checkup prevalence (`routine_checkup_within_1yr_pct`) centered against each state's baseline (`checkup_gap_pct_pts`). Meanwhile, `fcc_broadband_coverage_by_tract` is **modeled** from FCC Broadband Data Collection benchmarks, and clinic registries contain **CMS NPPES Type-2 Organizations only** (zero individual clinicians). Read `data_provenance` and state this plainly.
2. **Never include `routine_checkup_within_1yr_pct` or `state_mean_checkup_pct` as model features.** They define `checkup_gap_pct_pts` algebraically, causing instant `R^2 = 1.0` target leakage with zero weight on broadband, devices, or clinic distance.
3. **Drop one of the two collinear BSL columns.** In the modeled FCC table, `unserved_bsl_under_25_3_count` equals `satellite_only_bsl_count` on every row. Including both splits `ML.EXPLAIN_PREDICT` attributions arbitrarily.

---

## The four things you're working with

| Term | What it means |
|---|---|
| **Checkup Gap (`checkup_gap_pct_pts`)** | How many percentage points a census tract's annual routine checkup rate falls *below* its state mean (`> 0` means worse preventive-care utilization than the state baseline). Your **BigQuery ML** prediction target |
| **Barrier Attribution** | Per-tract top feature drivers returned by `ML.EXPLAIN_PREDICT`, showing whether unserved wireline locations, missing home devices, zero-vehicle isolation, uninsurance, or distance to safety-net care drives the predicted gap |
| **Double-Jeopardy Offline Desert** | A tract far from active safety-net clinics (or near a closed hospital) where households *also* lack wireline broadband and computing devices, meaning virtual care alone fails without mobile physical care or kiosks |
| **Intervention Allocation Plan** | Ranked priority tracts paired with their predicted checkup shortfall, top barrier attributions, matched intervention type, Equity Audit summary, and a board-ready grant memo |

The whole challenge is: **regional budget question in, attributed tract allocation plan out, backed by `ML.EXPLAIN_PREDICT` rather than guesswork.**

---

## Three tracks, one architecture

Every team shares the same spine: five tract and facility tables, a leakage-free BigQuery ML model trained with `CREATE MODEL`, per-tract feature attributions from `ML.EXPLAIN_PREDICT`, and an ADK planning agent that translates attributions into interventions. **What changes between tracks is the planning lens, not the underlying architecture.**

**These are starting points, not a cage.** Pick one, combine two, or define a sharper rural connectivity and preventive-care allocation workflow in the same vein if you can defend why it matters.

| Track | Planning trigger | Primary decision | What makes it hard |
|---|---|---|---|
| 🏥 **After a facility closure** | A rural hospital or clinic shut down (`historical_facility_closures_10yr`) | Triage surrounding tracts losing physical access | Separating neighborhoods where telehealth can absorb demand from offline tracts that need mobile vans |
| 📶 **This broadband & device grant cycle** | State digital-equity office allocating infrastructure subsidies vs. cellular tablet kits | Assign wireline subsidies (`unserved_bsl_share`) vs. LTE device kits (`cellular_only_share` + `no_device_share`) | Avoiding giving tablets where wireline/cellular infrastructure is missing, or laying fiber where affordability/devices are the real barrier |
| 🚐 **This FQHC operating year** | Regional safety-net network siting library telehealth kiosks vs. a weekly mobile health van | Match fixed kiosks vs. wheeled physical outreach (`nearest_safety_net_km` + `no_vehicle_share`) | Older rural tracts with high diabetes/hypertension (`diabetes_pct`) can face severe travel burdens even when baseline checkup rates vary |

---

## What you're building

**An access-equity planning assistant.** Not a static map, and not a wrapper around `SELECT * ORDER BY checkup_gap_pct_pts DESC`, but a conversational ADK agent that a state broadband or rural-health planner can interrogate as budgets, county boundaries, and intervention assumptions change.

Picture a Thursday afternoon inside a state rural-health and digital-equity office:

> **2:30pm, Thursday.** A regional grant committee has \$1.8M left to allocate across rural counties before Friday's filing deadline. Half the board wants to spend it all on telehealth tablet kits after a county hospital closure. Your planner needs proof of where tablets will work and where they will sit dark in a drawer.

Over the next hour the planner asks your agent:

| What they ask | What answers it |
|---|---|
| *"Which tracts in our state have the largest predicted routine checkup gap, and what is driving each one?"* | Custom tool calling `ML.EXPLAIN_PREDICT` on your leakage-free BigQuery ML model |
| *"Why does Tract A get cellular tablet kits while Tract B ten miles away gets a mobile clinic van?"* | Comparing top feature attributions (`no_device_share` + `cellular_only_share` vs. `unserved_bsl_share` + `nearest_safety_net_km` + `no_vehicle_share`) |
| *"Which tracts sit within 25 km of a closed hospital or clinic from the last ten years?"* | Spatial `ST_DISTANCE` join between `acs_income_and_device_ownership.tract_geom` and `historical_facility_closures_10yr.closure_geom` |
| *"How accurate is your model, and how do we know it isn't leaking the answer?"* | `ML.EVALUATE` metrics (`R^2` well below `1.0`, honest residual discussion) and feature-exclusion verification |
| *"If we cap tablet kits at 15 tracts and fund 3 telehealth kiosks near active FQHCs, which tracts make the cut?"* | Multi-turn constraint reasoning over model predictions + `active_health_facilities_registry` (`is_statutory_safety_net_clinic`) |
| *"Who lives in the tracts our plan prioritizes compared with the state as a whole?"* | Post-output Equity Audit joining `audit_*` demographic columns |
| *"Draft the two-page executive justification for tomorrow's grant board packet."* | Gemini synthesizing predictions, attributions, facility distances, data provenance caveats, and Equity Audit numbers |

### Questions that need more than we gave you

| The question | What you'd need to add |
|---|---|
| *"Real road drive time on rural highways instead of straight-line kilometers"* | Google Maps Routes API (`ST_DISTANCE` gives straight-line distance across rivers and mountain ridges) |
| *"Actual cellular carrier tower coverage polygons"* | Public FCC mobile coverage or state broadband award datasets (check [BYOD license rules](#bringing-your-own-data) first) |
| *"Save and compare three competing grant budget scenarios across sessions"* | Firestore, Cloud SQL, or AlloyDB scenario persistence |

---

## Now pick your state

**Choose one state for your deployment plan** (or train carefully with state awareness and allocate within one target state). Every state below pairs **five rural high-need counties** with **one urban comparator county** (`18` urban tracts per state):

| State | `FIPS` | Rural counties + *Urban comparator* | Tracts (`Rural` + `Urban`) | Unserved BSLs (`<25/3`) | No home internet | Active facilities (Safety-net) | 10-yr closures |
|---|---|---|---:|---:|---:|---:|---:|
| **MS** *(default)* | `28` | Leflore, Coahoma, Bolivar, Washington, Sunflower + *Hinds* | 65 (`47` + `18`) | 21.3% | 14.7% | 90 (`54`) | 18 |
| **AL** | `01` | Dallas, Wilcox, Perry, Lowndes, Sumter + *Jefferson* | 43 (`25` + `18`) | 15.6% | 10.4% | 89 (`53`) | 3 |
| **GA** | `13` | Dougherty, Terrell, Crisp, Ware, Emanuel + *Fulton* | 57 (`39` + `18`) | 20.6% | 12.9% | 90 (`54`) | 2 |
| **TX** | `48` | Hidalgo, Starr, Zavala, Cherokee, Nacogdoches + *Dallas* | 72 (`54` + `18`) | 19.0% | 11.0% | 90 (`54`) | 6 |
| **CA** | `06` | Madera, Merced, Fresno, Imperial, Shasta + *Santa Clara* | 101 (`83` + `18`) | 19.0% | 6.4% | 90 (`54`) | 6 |
| **NY** | `36` | Niagara, Chautauqua, St. Lawrence, Franklin, Delaware + *Bronx* | 90 (`72` + `18`) | 19.7% | 9.2% | 90 (`54`) | 3 |

Watch two signals before committing:

1. **Leading-zero FIPS (`AL` = `01`, `CA` = `06`):** Keep `census_tract_geoid` (11 characters) and `county_fips` (5 characters) as `STRING` everywhere so leading zeros are never stripped.
2. **Closure shock vs. urban-rural spread:** Mississippi (`MS`) carries **18** documented 10-year facility closures across the Delta, making it ideal for the post-closure track. California (`CA`, `101` tracts) and New York (`NY`, `90` tracts) offer the largest tract counts and sharp rural-vs-urban contrasts (*Imperial/Madera* vs. *Santa Clara*, or *St. Lawrence* vs. *Bronx*).

Write down your state, your track, and your scenario before opening an editor:

> *"We advise rural health and broadband allocation in ______. Following ______, our board must allocate resources across ______ counties between wireline subsidies, device kits, kiosks, and mobile care. Here is what our model predicts, and why."*

---

## The technology you'll use

| Component | Role |
|---|---|
| **ADK** (Agent Development Kit) | Build your agent in Python with ADK |
| **Gemini** | Synthesizing `ML.EXPLAIN_PREDICT` attributions, weighing trade-offs, and drafting grant justifications |
| **BigQuery** | Hosts your five tables (`a4i_telehealth`) and trains/serves your **BigQuery ML** model |
| **A Google-managed MCP server** | Consume at least one (BigQuery built-in MCP server or MCP Toolbox for Databases) |
| **At least one tool you built** | A Python function tool or custom MCP Toolbox tool wrapping `ML.EXPLAIN_PREDICT` and intervention matching |
| **Deployed to Google Cloud** | Live service running on **Agent Runtime** or **Cloud Run** |

**Also already set up for you, and worth ten seconds now rather than later: Antigravity.** Your Google Skills lab environment includes a button that launches the **Antigravity IDE**, and the **Antigravity CLI** is one word away in Cloud Shell (`agy`). Neither is required, and nothing here depends on them, so do not lose time fighting one if it is not helping, though we strongly recommend using at least one because every lane has tedious boilerplate a coding agent will happily absorb. [Details in Step 3](#strongly-recommended-antigravity-the-ide-and-the-cli).

### Choosing your MCP server

- **BigQuery's built-in MCP server** handles quick schema inspection and ad-hoc tract queries cleanly.
- **[MCP Toolbox for Databases](https://github.com/googleapis/mcp-toolbox)** lets you expose parameterized SQL tools over BigQuery (set `--min-instances=1` on Cloud Run to avoid demo cold starts).

### What "a tool you built" means, and why we ask

Your team must build at least one custom tool (in Python or MCP Toolbox) that goes beyond generic table reads: calling `ML.EXPLAIN_PREDICT`, inspecting top local feature attributions per tract, combining them with spatial clinic/closure proximity, and assigning a defensible intervention tier.

### And one required differentiator: **BigQuery ML (`CREATE MODEL` + `ML.EXPLAIN_PREDICT`)**

Why BigQuery ML belongs at the center of this problem:
- In earlier synthetic prototypes, targets generated from a formula allowed trivial `R^2 = 1.0` fits. Here, `checkup_gap_pct_pts` comes from **real empirical CDC PLACES surveillance**, so your model will achieve a realistic, imperfect fit (`R^2` well under `1.0`) and surface genuine residuals worth discussing.
- `LINEAR_REG` or `BOOSTED_TREE_REGRESSOR` with `ENABLE_GLOBAL_EXPLAIN = TRUE` lets your agent call `ML.EXPLAIN_PREDICT` live during a conversation, returning the exact top features (`top_k_features`) pushing each specific census tract's predicted checkup gap up or down.

See Section 13 of [`notebooks/c_telehealth_01_load_explore.ipynb`](notebooks/c_telehealth_01_load_explore.ipynb) for the leakage-free `v_tract_training_features` view and model DDL.

---

## Getting started

### Step 0: Organize your team

1. **Pick a team lead** and **a repo owner**.
2. **Choose your state and track** in five minutes.
3. **Split into four parallel lanes:**

#### Data lane (2 to 3 people)

- Run `notebooks/c_telehealth_01_load_explore.ipynb` (or `bash scripts/load.sh <STATE>`) to load and validate `a4i_telehealth`.
- Build your leakage-free, collinearity-free, race-free feature view (`Section 13`), train your BigQuery ML model (`CREATE OR REPLACE MODEL`), check `ML.EVALUATE`, and hand the exact `ML.EXPLAIN_PREDICT` SQL to the agent lane early.
- Compute spatial proximity to active safety-net clinics and 10-year closures (`ST_DISTANCE`).
- Run the post-output **Equity Audit** (`Section 11`) joining `audit_*` demographic shares to your prioritized tracts.

#### Agent lane (2 to 3 people)

- Build the Python ADK agent in `agent/` consuming at least one Google-managed MCP server and at least one custom tool invoking `ML.EXPLAIN_PREDICT`.
- Encode intervention decision rules so the agent never recommends video-only solutions in double-jeopardy offline deserts without connectivity.
- Deploy early to **Cloud Run** or **Agent Runtime**.

#### Front end lane (2 people)

Three routes. **Pick deliberately and be ready to say why**, because your interface choice tells judges who you think the user is.

| Option | Strength | Trade-off |
|---|---|---|
| **`adk web`** | Fastest. Built in, works immediately, and where you should start | Developer tool look and feel. Fine while building, weak as a final product story unless justified |
| **Gemini Enterprise** | Clean internal staff UX over Agent Runtime with minimal front-end code | Serves **internal** staff rather than the public (which fits a state broadband or rural-health analyst persona well if stated on purpose) |
| **Custom web UI** | Full control: an interactive tract allocation table or map displaying `ML.EXPLAIN_PREDICT` drivers beats a raw chat log | Most work by far. Scope tightly so it finishes on time |

- **Do not wait for a working agent.** Mock the response schema now, build against it, and swap in the live endpoint once the agent lane deploys.
- **Whatever you build, the recorded demo runs on it.** Test it end to end before recording.

#### Story lane (1 to 2 people, starting at minute zero)

Upload **four required artifacts** to https://portal.angelhack.com/a4i-console before deadline:

1. **Public GitHub repository link**
2. **Google Skills project link** (with live deployed agent)
3. **Pitch deck** (problem, state & track, `ML.EVALUATE` honesty, plain-words data provenance, `audit_*` Equity Audit results, and limitations)
4. **Pitch video (maximum 3 minutes)**: narrated screen-share walkthrough of a live run of your deployed agent

Judges score asynchronously from those four artifacts alone, with no live table Q&A.

### Your output artifact: the Intervention Allocation Plan

Your agent should produce a concrete allocation brief a state board could vote on:

- **Ranked priority census tracts** in your chosen state with `predicted_checkup_gap_pct_pts`
- **Per-tract `ML.EXPLAIN_PREDICT` barrier attributions** (the top 3 local drivers in plain English)
- **Recommended intervention per tract** (wireline subsidy, cellular tablet kit, library/FQHC telehealth kiosk, or mobile clinic van) with nearby safety-net clinic / closure context
- **Post-output Equity Audit summary** comparing prioritized tracts against the state baseline
- **Drafted grant board justification memo**

### Step 1: Create the team repository

**Repo owner only.**

1. At the top of this page, click the green **Use this template** button -> **Create a new repository**. *(No button? Use **Fork** and tell a coach.)*
2. Name it after your team, choose **Public**, and click **Create repository**.
3. Go to **Settings -> Collaborators** and add every teammate's GitHub username.
4. Paste the repo URL where everyone on your team can see it.

### Step 2: Get into your Google Cloud project

Follow your facilitator's instructions to open your shared Google Skills project. **There is one project per team.** You all share Owner access and see the same BigQuery datasets, so coordinate dataset, model, and Cloud Run service names.

### Step 3: Everyone: get into Cloud Shell

**Cloud Shell is where you will work** (alongside your preconfigured Antigravity workstation if provided at your venue). It already has `gcloud`, `bq`, Python, Node, `git`, Docker, and the Antigravity CLI (`agy`) installed.

1. In the Google Cloud console, click the **terminal icon (`>_`) in the top right** so Cloud Shell opens attached to *this* project and browser session.
2. Clone your team's repository and enter it:

   ```bash
   git clone https://github.com/YOUR-TEAM/YOUR-REPO.git
   cd YOUR-REPO
   ```

3. Open the repository as a workspace in Cloud Shell Editor:

   ```bash
   cloudshell workspace .
   ```

#### One repo, one branch per lane

Eight to ten people committing straight to `main` will collide right before submission. Create a branch per lane from minute one:

```bash
git checkout -b data        # or agent, frontend, story
```

Merge into `main` whenever your lane has something another lane needs (such as the `ML.EXPLAIN_PREDICT` SQL or the deployed agent URL). Keep your files inside `$HOME` (your cloned repo), because `$HOME` persists across Cloud Shell restarts while directories outside it do not.

Helpful references:
[Using Cloud Shell](https://docs.cloud.google.com/shell/docs/using-cloud-shell)
·
[Cloud Shell Editor overview](https://docs.cloud.google.com/shell/docs/editor-overview)

#### Strongly recommended: Antigravity, the IDE and the CLI

Antigravity is Google's agentic coding environment, already available in two forms:

- **The Antigravity IDE:** Launched from the button in your Google Skills lab environment. It reads your repository, proposes multi-file edits you review before accepting, runs terminal commands, and tests in a browser.
- **The Antigravity CLI (`agy`):** Preinstalled in Cloud Shell with zero setup:

  ```bash
  agy
  ```

  Where it saves the most time in a 4.5-hour sprint:
  - **Agent lane:** scaffolding ADK boilerplate, wrapping your `ML.EXPLAIN_PREDICT` query inside a Python tool, and drafting Cloud Run deployment configs.
  - **Data lane:** iterating on leakage-free feature engineering SQL, spatial `ST_DISTANCE` joins, and post-output Equity Audit queries.
  - **Anyone stuck on an error:** paste the traceback and let it inspect your actual files. Use `/diff` to review pending edits before accepting and `/permissions` to control autonomy.

[Antigravity: getting started](https://antigravity.google/docs/getting-started)
·
[IDE overview](https://antigravity.google/docs/ide/overview/)
·
[CLI install and auth](https://antigravity.google/docs/cli/install)
·
[CLI hands-on codelab](https://codelabs.developers.google.com/antigravity-cli-hands-on)

### Step 4: Load the data

**Data lane's job.** One person runs it while the other lanes start immediately.

1. In the Google Cloud console, search for **Colab Enterprise** and open it.
2. **You will be prompted to enable required APIs. Accept them.** When the Colab Enterprise home page loads, it often displays a *second* **Enable APIs** banner at the top. Click that too. Seeing two prompts on a fresh project is expected.
3. Go to **My Notebooks** -> **Import** -> source **URL**, and paste this raw notebook URL:

   ```text
   https://raw.githubusercontent.com/Bornism/A4I2026-challenge-telehealth/main/notebooks/c_telehealth_01_load_explore.ipynb
   ```

   *(If your team modifies the notebook later, get your own copy's raw URL by opening the file on GitHub and clicking **Raw**.)*
4. Click **Import**, open the notebook, set `STATE` (`MS`, `AL`, `GA`, `TX`, `CA`, or `NY`) in the first code cell, and run the cells top to bottom. Read the markdown explanations between cells: Section 2 demonstrates Simpson's paradox across states and `R^2 = 1.0` target leakage, and Section 12 validates every table.

**Headless CLI Fallback (`scripts/load.sh`):**
If Colab Enterprise is slow or unavailable, run the headless loader from your cloned repository root in Cloud Shell:

```bash
bash scripts/load.sh                 # defaults to MS (Mississippi)
bash scripts/load.sh CA              # or AL, GA, TX, NY
bash scripts/load.sh --list          # list all six pre-staged states
```

Invoke it with `bash` rather than `./scripts/load.sh` so file permissions never block you. Every run replaces tables cleanly (`--replace`), so switching states or re-running is completely safe.

### What you'll have

Five validated tables in `<your-project>.a4i_telehealth` for your selected state (default `MS` counts shown alongside the 6-state starter pack total):

| Table | Grain | Loaded rows (`MS` default) | 6-state pack total | Provenance summary |
|---|---|---:|---:|---|
| `cdc_tract_health_utilization` | 1 row / census tract | 65 | 428 | **100% real empirical** CDC PLACES (`cwsq-ngmh`) checkup gap & chronic burden |
| `acs_income_and_device_ownership` | 1 row / census tract | 65 | 428 | **Real public** US Census ACS internet, cellular-only, device, vehicle, poverty & `audit_*` shares |
| `fcc_broadband_coverage_by_tract` | 1 row / census tract | 65 | 428 | **Modeled** BSL speed-tier counts calibrated to FCC BDC & ACS baselines |
| `active_health_facilities_registry` | 1 row / organization | 90 | 539 | **Real public organizations only** (CMS NPPES Type-2 clinics + HRSA HPSA scores) |
| `historical_facility_closures_10yr` | 1 row / closure event | 18 | 38 | **Real public organizations only** (UNC Sheps Center rural hospital closures & deactivated Type-2 clinics) |

---

## The data, and why we chose it

- **Health utilization is 100% empirical.** CDC PLACES (`cwsq-ngmh`) provides census-tract routine checkup rates (`CHECKUP`), uninsurance, diabetes, hypertension, and disability. Notice in Section 4 that older rural tracts with high chronic disease often report steady annual checkups despite losing nearby hospitals, making preventive checkup shortfall and chronic-care travel burden distinct dimensions worth separating.
- **Broadband location counts are modeled** (`fcc_broadband_coverage_by_tract`), calibrated to FCC Broadband Data Collection benchmarks. State this plainly rather than presenting BSL counts as raw FCC fabric filings.
- **Facilities are strictly organizational** (`entity_type_code = 2`), so zero individual doctors or private home addresses appear anywhere.

### One thing we deliberately excluded from training

Never pass `audit_black_share`, `audit_hispanic_share`, `audit_asian_share`, `audit_indigenous_share`, or `audit_white_share` into `CREATE MODEL`. Train strictly on structural infrastructure, economic, and spatial access variables, then join `audit_*` afterward to audit who your allocation plan serves.

### What "auditing the outcome" actually means

1. Generate your top-priority tracts and matched interventions for your state.
2. Join those tracts back to `acs_income_and_device_ownership` (`audit_*` columns, `poverty_rate`, `no_vehicle_rate`, and `fcc_broadband_coverage_by_tract.rural_urban_context`).
3. Compare against the full state table: **did an uncalibrated score funnel every dollar into dense urban tracts (because population counts are larger) while stranding rural hospital-closure tracts, or vice versa?** Report the exact numbers in your deck and video.

---

## Going further

### What will set yours apart

- **Compare model families honestly.** Train a fast interpretable `LINEAR_REG` baseline alongside a regularized or tree-based BQML model, inspect `ML.EVALUATE`, and explain why a realistic `R^2` on empirical public-health data beats a leaked `1.0`.
- **Budget-constrained optimization.** Let the planner specify a dollar budget (with unit costs per BSL subsidy, tablet kit, kiosk, and mobile van stop) and optimize coverage across tracts.
- **Separate preventive checkup gaps from chronic-disease isolation.** Build a composite triage view for rural tracts high in `diabetes_pct` / `hypertension_pct` sitting near recent hospital closures.

### The add-on we'd build if we had another four hours

**A community anchor-institution site verifier.** Before placing a community telehealth kiosk in an underserved tract, have an agent check nearby public libraries, FQHCs (`is_statutory_safety_net_clinic`), and transit/walkability constraints, drafting an operational site-readiness checklist for local county health staff.

---

## Bringing your own data

**Augment, do not replace.** Any external dataset you load must pass all six licensing rules:

| Rule | Why |
|---|---|
| ❌ No **NonCommercial** (`CC BY-NC`) | Winning projects are promoted commercially |
| ❌ No **NoDerivatives** (`CC BY-ND`) | Derived modeling and outputs are required |
| ❌ No **Share-Alike** (`ODbL`, `CC BY-SA`) | Encumbers your team's work |
| ❌ No **individual-level personal data (PII)** | Aggregate public statistics and organizational facilities only |
| ❌ No **unstated license** | Unlicensed web tables cannot be redistributed |
| ✅ **Public domain, CC0, US Government works** | Safe |

**The license trap most likely to catch you:** anything derived from **OpenStreetMap carries the `ODbL` share-alike license**, and commercial speed-test aggregators (such as proprietary ISP coverage maps) are almost always NonCommercial or all-rights-reserved. Check the license before loading, and ask a coach if you are unsure.

---

## What's in this repository

```text
README.md                                         This challenge brief and team runbook.
notebooks/c_telehealth_01_load_explore.ipynb      Step 1: Load, explore, and validate all 5 tables.
notebooks/c_telehealth_90_publish_snapshot.ipynb  Maintainers only (publishes snapshots to Cloud Storage).
scripts/load.sh                                   Headless CLI fallback that loads and verifies your state.
scripts/README.md                                 Usage and verification notes for scripts/load.sh.
data/*.parquet                                    Pre-staged 6-state GeoParquet starter tables (see data/README.md).
agent/                                            Empty on purpose. Your ADK agent goes here.
```

---

## How you'll be judged

**"Finished" is not the goalpost.** Almost nobody completes every stretch idea in 4.5 hours. A team that gets three quarters of the way with clean modeling discipline, genuine `ML.EXPLAIN_PREDICT` attributions, and honest limitations will beat a team that demos something polished and hollow.

**You are judged against the track you chose**, not against a fixed answer key. State your chosen state and track right at the beginning of your deck and video.

**Judges score your submission asynchronously, not a live Q&A.** Put the answers to the questions below directly into your deck and your **<=3-minute pitch video**:

| Dimension | Weight | The question judges are asking |
|---|---:|---|
| **Impact & insight** | 30 | Would a state broadband or rural-health planner actually defend this allocation to a grant board? |
| **Technical execution** | 30 | Does the deployed ADK agent work end to end, using MCP, a custom tool, and genuine `CREATE MODEL` + `ML.EXPLAIN_PREDICT`? |
| **Rigor & judgment** | 25 | Did you avoid target leakage and BSL collinearity, state empirical vs. modeled data honestly, and present quantitative `audit_*` Equity Audit findings? |
| **Craft & communication** | 15 | Does your <=3-minute video show a crisp live run, and can you defend your interface choice? |
| **Bonus: range** | **+10** | Thoughtful extensions (cost optimization, BYOD layers, multi-agent workflows) that strengthen the decision |

Bonus sits **on top** of the 100, so ambition never cannibalizes the fundamentals. Nail the core workflow and add nothing extra, and you can still win.

### What "Rigor and judgment" actually means

This is a quarter of your score and the easiest place to stand out:

1. **Data decisions you can defend:** Know plainly that CDC PLACES checkup rates, ACS internet/device counts, and organizational CMS NPPES facilities are empirical public records, whereas `fcc_broadband_coverage_by_tract` is modeled from FCC BDC benchmarks.
2. **Validation and leakage discipline:** Show `ML.EVALUATE` in your deck or video. An `R^2` of `1.00` on this dataset is a target-leakage bug (`routine_checkup_within_1yr_pct` left in features), not a triumph, and dropping one of the two identical BSL columns avoids splitting `ML.EXPLAIN_PREDICT` weights.
3. **Bias handling:** Keep `audit_*` columns out of `CREATE MODEL`, run the post-output Equity Audit (`Section 11`), and report actual numbers comparing your prioritized tracts against the state baseline.
4. **Knowing what virtual care cannot solve:** A tablet cannot replace inpatient emergency care after a rural hospital closure when households also lack vehicles and broadband. Volunteering that boundary shows genuine domain judgment.

### A note on decisions generally

Which state you pick, whether you train on one state or pool states with state centering, how you translate top attributions into intervention tiers, and which UI you build have no single right answer. Judges reward teams who choose on purpose and explain why.

---

## Getting help

Ask your **Table Captain** first, then the **ROI facilitator** on the floor and the event Discord channel. If anything looks wrong with your dataset, run **Section 14 (Diagnostic summary)** at the bottom of `notebooks/c_telehealth_01_load_explore.ipynb` and share the output block.
