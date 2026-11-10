# Your agent goes here

This folder is empty on purpose.

We built the on-ramp: empirical CDC PLACES routine checkup surveillance, American Community Survey household internet and device counts, modeled FCC Broadband Data Collection location tiers, organizational CMS NPPES clinic registries and ten-year rural closure logs, and a validation suite that checks every table before you start. We did not build the vehicle. The design decisions in your agent are what you will be judged on.

## What has to be true of what you build here

- **An ADK agent**, in Python.
- **At least one tool you built yourself.** A Python function tool or one you defined in MCP Toolbox both count. Your custom tool should invoke `ML.EXPLAIN_PREDICT` (or `ML.PREDICT` paired with attribution logic) against the BigQuery ML model your data lane trains, and translate per-tract barrier attributions into concrete resource allocations (wireline subsidies, cellular tablet kits, community telehealth kiosks, or mobile clinic vans). Consuming only prebuilt generic tools and calling that your design does not count.
- **At least one Google-managed MCP server, consumed.** Do not author your own from scratch. Use BigQuery's built-in MCP server or the [MCP Toolbox for Databases](https://github.com/googleapis/mcp-toolbox).
- **Deployed to Google Cloud**, on Agent Runtime or Cloud Run (your choice).
- **Your required differentiator: BigQuery ML.** Your agent must call a genuine BigQuery ML model (`CREATE MODEL` + `ML.EXPLAIN_PREDICT`) predicting `checkup_gap_pct_pts` without target leakage and without training on `audit_*` demographic columns. Querying historical averages alone does not count.

## The thing worth remembering while you build

The per-feature attributions that come back from `ML.EXPLAIN_PREDICT` are what turn a tract ranking into an intervention a state broadband or rural-health board can defend. Two neighborhoods with the exact same predicted checkup shortfall can need completely different interventions: one has cellular coverage and zero tablets, while the other lost its hospital and has neither wireline broadband nor vehicles ("double-jeopardy offline deserts"). Do not treat explanation as a reporting step at the end. It is the product.

See Section 13 of [`notebooks/c_telehealth_01_load_explore.ipynb`](../notebooks/c_telehealth_01_load_explore.ipynb) for the leakage-free feature view, model DDL, and syntax rules.
