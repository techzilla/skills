---
name: kibana-dashboards
description: >
  Create, search, and manage Kibana Dashboards and Lens visualizations. Use when you need to
  find existing dashboards, define dashboards and visualizations declaratively, version control
  them, or automate their deployment.
metadata:
  author: techzilla
  version: 0.4.0
  universal: true
  derived_from: elastic/agent-skills v0.6.0 (Apache-2.0), modified
compatibility: Kibana 9.4 or later (Dashboards and Visualizations APIs) with matching
  Elasticsearch, self-managed, Elastic Cloud Hosted, or Elastic Cloud Serverless.
  Written for and verified against `elastic` CLI 0.7.0.
---

# Kibana Dashboards and Lens Visualizations

Search, create, update, and delete Kibana dashboards and standalone Lens visualizations using the Kibana 9.4+ Dashboards
and Visualizations APIs. Produce minimal, diffable JSON bodies; prefer inline panel definitions over library references;
and choose the correct dataset type (data view vs ES|QL) before writing metrics or chart layers.

## Environment Configuration

This skill executes Kibana operations through the `elastic` CLI **0.7.0**. If the
[`elastic` CLI](https://github.com/elastic/cli#configuration) is not installed, tell the user what it is needed for. Do
not guess credentials or call the HTTP API directly; use only the workarounds documented here.

Operations are written in HTTP-shorthand form (e.g., `GET kbn:/api/dashboards`). The [Operations](#operations) table maps
each to its CLI command. Commands taking `--input-file` read a JSON object of the request's query/body fields.

## Version gate (Kibana < 9.5)

CLI 0.7.0 marks every `elastic kb dashboards` and `elastic kb visualizations` command as Kibana 9.5+ and hides them when
the context's detected Kibana version is older. On 9.4 these APIs exist (technical preview) but the commands are
absent from `--help` and fail as unknown.

- **Workaround (preferred):** ask the user to pin the version in the context's `kibana` block of the CLI config, then
  retry. Do not edit the config without approval.

  ```yaml
  kibana:
    version: "9.5"
  ```

- **Workaround (search only, no pin):** use `get-saved-objects-find` (see [Searching](#searching)). Stack only.
- 9.4 list responses return items under `dashboards` / `visualizations` with top-level `total`; 9.5+ uses `data` and
  `meta`.

## Prerequisites

**ES|QL placement:**

- Standalone library charts: `PUT kbn:/api/visualizations/{id}` with `data_source.type: "esql"`.
- ES|QL panels embedded in a dashboard: inline `vis` panel `config` with `data_source.type: "esql"` via
  `PUT kbn:/api/dashboards/{id}`.
- Do not use `data_source.type: "data_view_reference"` or index-pattern aggregations when the user explicitly requests
  ES|QL — the persisted Lens state must use a text-based ES|QL datasource (`textBased` / `esql`), not a data-view count
  operation.

## Process

1. **Verify Kibana connectivity.** Call `GET kbn:/api/status`. If the call fails, stop and surface the error. Read
   `version.number`; below 9.5, apply the [Version gate](#version-gate-kibana--95).

2. **Classify the task.** Decide whether the user needs a **dashboard** (collection of panels, optional time range), a
   **standalone Lens visualization** (library item referenced by id or used alone), or **both**. Determine whether a
   deterministic saved-object id was supplied — when given, use upsert (`PUT`) with that id rather than `POST` (which
   auto-generates ids).

3. **Choose the dataset type before building metrics or layers.**

   | User intent                                      | Dataset                                                                    | Metric / axis pattern                                                                                                                    |
   | ------------------------------------------------ | -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
   | Simple count or aggregation on a saved data view | `data_source.type: "data_view_reference"` with `ref_id`                    | `metrics: [{ type: "primary", operation: "count" }]` (or other aggregation operations)                                                   |
   | Ad-hoc index pattern                             | `data_source.type: "data_view_spec"` with `index_pattern` and `time_field` | Same aggregation `operation` fields                                                                                                      |
   | ES\|QL query (explicit or complex logic)         | `data_source.type: "esql"` with `query`                                    | `metrics: [{ type: "primary", column: "<alias>" }]` or layer axes `{ column: "<alias>" }` — **never** `operation: "count"` on the metric |

   Write the aggregation in the ES|QL query (`STATS count = COUNT()`), then reference the resulting column by name.

4. **Build a dashboard body when creating or updating dashboards.** The request body is flat — `title`, `panels`, and
   optional `time_range` at the root. Do not wrap in `{ data: ... }` on write. Required fields:
   - `title` — exact string the user requested.
   - `panels` — array; use `[]` when the user asks for an empty dashboard (do not omit the key or invent panels).
   - `time_range` — when the user specifies a default time filter, set `{ "from": "<expr>", "to": "<expr>" }` (for
     example `{ "from": "now-7d", "to": "now" }`). Supplying `time_range` persists the dashboard time filter on open
     (equivalent to enabling time restore in the UI).

   **Upsert with a deterministic id:**

   ```json
   {
     "title": "Sales Overview",
     "panels": [],
     "time_range": { "from": "now-7d", "to": "now" }
   }
   ```

   Call `PUT kbn:/api/dashboards/eval-sales-overview` with the body above when the user supplies that id.

   **Inline ES|QL metric panel example** (inside `panels`):

   ```json
   {
     "type": "vis",
     "id": "total-requests",
     "grid": { "x": 0, "y": 0, "w": 12, "h": 6 },
     "config": {
       "title": "Total Requests",
       "type": "metric",
       "data_source": {
         "type": "esql",
         "query": "FROM logs* | STATS count = COUNT()"
       },
       "metrics": [{ "type": "primary", "column": "count" }]
     }
   }
   ```

   Prefer inline `config` properties over `config.ref_id` for portable dashboards. Read
   [Dashboard API Reference](references/dashboard-api-reference.md) for panel types, grid layout, and copy workflows.

5. **Build a standalone Lens visualization when the user asks for a library chart.** Use the Visualizations API. Upsert
   with `PUT kbn:/api/visualizations/{id}` when an id is supplied; otherwise `POST kbn:/api/visualizations` and report
   the generated id from the response.

   **ES|QL metric (total count from logs):**

   ```json
   {
     "type": "metric",
     "title": "Total Requests",
     "data_source": {
       "type": "esql",
       "query": "FROM logs* | STATS count = COUNT()"
     },
     "metrics": [{ "type": "primary", "column": "count" }]
   }
   ```

   Call `PUT kbn:/api/visualizations/eval-total-requests` when that id is required. The API persists a Lens saved object
   whose datasource state uses ES|QL (`textBased` / `esql`), not an index-pattern aggregation.

   Read [Lens API Reference](references/lens-api-reference.md) and
   [Chart Types Reference](references/chart-types-reference.md) for xy, gauge, heatmap, and other chart schemas.

6. **Execute and confirm.** Perform the write with `PUT kbn:/api/dashboards/{id}` or `PUT kbn:/api/visualizations/{id}`
   (or `POST` when no id is supplied). Confirm with `GET kbn:/api/dashboards/{id}` or
   `GET kbn:/api/visualizations/{id}`. Report the id and title back to the user — do not claim success without a
   successful read-back.

7. **Search, export, or delete when requested.** Find objects per [Searching](#searching) — filter server-side; do not
   list everything and scan. Delete with `DELETE kbn:/api/dashboards/{id}` or `DELETE kbn:/api/visualizations/{id}`.
   For bulk export or import, use `POST kbn:/api/saved_objects/_export` or `POST kbn:/api/saved_objects/_import`.

## Searching

`--query` uses `simple_query_string` against `title` and `description`; all words must match.

```sh
elastic kb dashboards search-dashboards --query 'nginx*' --per-page 50 --page 1
elastic kb visualizations search-visualizations --query 'requests*' --per-page 50
```

**Tag filters:** CLI 0.7.0 sends array flags (`--tags`, `--excluded-tags`, `--tag-names`, `--excluded-tag-names`) as a
JSON string (`tags=["a"]`), which Kibana reads as one literal tag id, so they match nothing. Pass a single tag id as a
plain string through `--input-file` with `--no-validate`; run one call per tag and merge results.

```sh
echo '{"query":"nginx*","tags":"<tag-id>","per_page":50}' > q.json
elastic kb dashboards search-dashboards --input-file q.json --no-validate
```

`tag_names` / `excluded_tag_names` require Kibana 9.6+; resolve names to ids instead:

```sh
echo '{"type":"tag","search":"<tag-name>","search_fields":"name"}' > t.json
elastic kb saved-objects get-saved-objects-find --input-file t.json --no-validate
```

**Saved-objects search** (works without the version pin; stack only). `--type` and `--has-reference` are mis-encoded by
CLI 0.7.0, so always use `--input-file` with string values and `--no-validate`:

```sh
echo '{"type":"dashboard","search":"nginx*","search_fields":"title","has_reference":"{\"type\":\"tag\",\"id\":\"<tag-id>\"}","per_page":50}' > f.json
elastic kb saved-objects get-saved-objects-find --input-file f.json --no-validate
```

## Dashboard grid

Dashboards use a **48-column** grid. On 16:9 screens, roughly **20–24 rows** fit above the fold — target **8–12 panels**
in that band.

| Width   | Columns | Height (rows) | Use case                 |
| ------- | ------- | ------------- | ------------------------ |
| Full    | 48      | 14–16         | Wide time series, tables |
| Half    | 24      | 10–12         | Primary charts           |
| Quarter | 12      | 5–6           | KPI metrics              |
| Sixth   | 8       | 4–5           | Dense metric rows        |

**Grid packing:** When stacking rows, set the next panel's `y` to the previous panel's `y + h`. Panels sharing a row
should use the same `h`. Do not add markdown panels as dashboard titles — use descriptive chart titles instead.

## ES|QL patterns

**Time series bucket** (dashboard time picker injects `?_tstart` / `?_tend`):

```esql
FROM logs*
| WHERE @timestamp <= ?_tend AND @timestamp > ?_tstart
| STATS count = COUNT() BY BUCKET(@timestamp, 75, ?_tstart, ?_tend)
```

Set `"scale": "temporal"` on the x-axis for time-series xy charts. See
[Chart Types Reference](references/chart-types-reference.md) for axis and layer details.

**Static reference values** — use `EVAL` in the query, then reference the column:

```esql
FROM logs* | STATS count = COUNT() | EVAL goal = 15000
```

## Examples

Example JSON definitions live under [assets/](assets/): `dashboard-basic.json`, `demo-dashboard.json`,
`dashboard-with-visualizations.json`, `ecommerce-analytics-dashboard.json`, `metric-esql.json`, `bar-chart-esql.json`,
`line-chart-timeseries.json`, `datatable.json`.

## Guidelines

1. **Match the user's id and title exactly** when supplied — do not substitute auto-generated ids.
2. **Honor empty panels** — when the user asks for `panels: []`, send an empty array; do not add placeholder panels.
3. **ES|QL when requested** — use `data_source.type: "esql"` and column references; never satisfy an ES|QL request with
   `operation: "count"` on a data view.
4. **Minimal payloads** — omit derivable defaults; let the API inject styling and metadata.
5. **Confirm writes** — always read back with `GET` after create or update.
6. **Read references before complex charts** — metric and xy schemas differ between data view and ES|QL; consult
   [Chart Types Reference](references/chart-types-reference.md) before generating partition or table charts.

## Common issues

| Error                                      | Likely cause                         | Fix                                                                          |
| ------------------------------------------ | ------------------------------------ | ---------------------------------------------------------------------------- |
| `dashboards` / `visualizations` missing    | Kibana < 9.5 detected                | See [Version gate](#version-gate-kibana--95)                                 |
| Tag filter returns nothing                 | CLI array encoding                   | Use `--input-file` with a string value and `--no-validate`                   |
| `must be array` validation error           | String value in `--input-file`       | Add `--no-validate`                                                          |
| `Pass --yes to confirm`                    | Delete without confirmation          | Add `--yes`                                                                  |
| 404 on GET after PUT                       | Wrong id or space                    | Confirm id and retry `GET kbn:/api/dashboards/{id}`                          |
| 400 validation                             | ES\|QL column mismatch               | Align `metrics[].column` / layer `column` with `STATS` aliases in the query  |
| ES\|QL panel saved as data view            | Wrong dataset type                   | Use `data_source.type: "esql"`, not `data_view_reference`                    |
| Empty dashboard missing time filter        | Omitted `time_range`                 | Include `{ "from": "now-7d", "to": "now" }` when a default range is required |
| XY chart failure                           | Missing layer `data_source`          | Put `data_source` inside each layer, not only at the root                    |

## Operations

Verified against CLI 0.7.0. For a non-default space, use a context whose `kibana.url` ends in `/s/<space-id>`; select it
with `--use-context <name>`.

| HTTP API (shorthand)                  | `elastic` CLI command                                                                                     | Kibana |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------- | ------ |
| `GET kbn:/api/status`                 | `elastic kb system get-status`                                                                            | all    |
| `GET kbn:/api/dashboards`             | `elastic kb dashboards search-dashboards [--query '<q>'] [--page N] [--per-page N]`                       | 9.5+\* |
| `GET kbn:/api/dashboards/{id}`        | `elastic kb dashboards get-dashboard --id '<id>'`                                                         | 9.5+\* |
| `POST kbn:/api/dashboards`            | `elastic kb dashboards create-dashboard --input-file '<path.json>'`                                       | 9.5+\* |
| `PUT kbn:/api/dashboards/{id}`        | `elastic kb dashboards upsert-dashboard --id '<id>' --input-file '<path.json>'`                           | 9.5+\* |
| `DELETE kbn:/api/dashboards/{id}`     | `elastic kb dashboards delete-dashboard --id '<id>' --yes`                                                | 9.5+\* |
| `GET kbn:/api/visualizations`         | `elastic kb visualizations search-visualizations [--query '<q>'] [--page N] [--per-page N]`               | 9.5+\* |
| `GET kbn:/api/visualizations/{id}`    | `elastic kb visualizations get-visualization --id '<id>'`                                                 | 9.5+\* |
| `POST kbn:/api/visualizations`        | `elastic kb visualizations create-visualization --input-file '<path.json>'`                               | 9.5+\* |
| `PUT kbn:/api/visualizations/{id}`    | `elastic kb visualizations upsert-visualization --id '<id>' --input-file '<path.json>'`                   | 9.5+\* |
| `DELETE kbn:/api/visualizations/{id}` | `elastic kb visualizations delete-visualization --id '<id>' --yes`                                        | 9.5+\* |
| `GET kbn:/api/saved_objects/_find`    | `elastic kb saved-objects get-saved-objects-find --input-file '<path.json>' --no-validate`                | stack  |
| `POST kbn:/api/saved_objects/_export` | `elastic kb saved-objects post-saved-objects-export --objects '[{"type":"<type>","id":"<id>"}]'`          | all    |
| `POST kbn:/api/saved_objects/_import` | `elastic kb saved-objects post-saved-objects-import --file '<path.ndjson>' --overwrite`                   | all    |

\* Works on 9.4 with the [version pin](#version-gate-kibana--95).
