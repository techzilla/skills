---
name: kibana-dashboards
description: >
  Create, search, and manage Kibana Dashboards and Lens visualizations. Use when you need to
  find existing dashboards, define dashboards and visualizations declaratively, version control
  them, or automate their deployment.
metadata:
  author: techzilla
  version: 0.5.0
  universal: true
  derived_from: elastic/agent-skills v0.6.0 (Apache-2.0), modified
compatibility: Kibana 9.x stack (self-managed or Elastic Cloud Hosted) or Elastic Cloud Serverless. Dashboards and
  Visualizations API commands need Kibana 9.5+ or Serverless; saved-objects procedures work on any 9.x. Written for and
  verified against `elastic` CLI 0.7.0. Saved-objects procedures require `jq`.
---

# Kibana Dashboards and Lens Visualizations

Search, create, update, and delete Kibana dashboards and standalone Lens visualizations using the Kibana 9.5+ Dashboards
and Visualizations APIs, or the saved objects API where those can't be used. Produce minimal, diffable JSON bodies;
prefer inline panel definitions over library references; and choose the correct dataset type (data view vs ES|QL)
before writing metrics or chart layers.

## Environment Configuration

This skill executes Kibana operations through the `elastic` CLI **0.7.0**. If the
[`elastic` CLI](https://github.com/elastic/cli#configuration) is not installed, tell the user what it is needed for. Do
not guess credentials or call the HTTP API directly; use only the workarounds documented here.

Operations are written in HTTP-shorthand form (e.g., `GET kbn:/api/dashboards`). The [Operations](#operations) table maps
each to its CLI command. Commands taking `--input-file` read a JSON object of the request's query/body fields.

## Choosing an API

| Kibana              | `elastic kb dashboards` / `visualizations`                          | Use                                        |
| ------------------- | ------------------------------------------------------------------- | ------------------------------------------ |
| 9.5+ or Serverless  | Available                                                           | Dashboards/Visualizations API              |
| 9.4                 | Hidden by CLI 0.7.0 (the API exists only as a technical preview)    | [Saved objects route](#saved-objects-route) |
| < 9.4               | API does not exist                                                  | [Saved objects route](#saved-objects-route) |

Never pin a false `version` in the CLI config to unhide commands.

**Also use the saved objects route on 9.5+** to modify a dashboard the Dashboards API cannot round-trip. Never
`upsert-dashboard` a dashboard whose `get-dashboard` response has a top-level `warnings` array: unsupported panels are
reported there as `dropped_panel` and unmapped keys are stripped on read, so writing it back deletes them.

- **Links panels:** the 9.4 Dashboards API has no links panel schema, so it cannot preserve them. 9.5+ supports them but
  strips each panel's `enhancements` (drilldowns) and `disabledActions`. Edit dashboards with links panels via saved
  objects.

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
   `version.number` and `version.build_flavor`, then pick the route per [Choosing an API](#choosing-an-api). **Stack
   below 9.5:** stop here and follow the [Saved objects route](#saved-objects-route) instead of steps 2–7, which use
   the Dashboards/Visualizations API.

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
   For bulk export, import, or copying between clusters, use the [Saved objects route](#saved-objects-route).

## Searching

Dashboards/Visualizations API (9.5+ or Serverless). On older versions, search per the
[Saved objects route](#saved-objects-route). `--query` uses `simple_query_string` against `title` and `description`;
all words must match.

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

`tag_names` / `excluded_tag_names` require Kibana 9.6+; resolve names to ids instead (any version):

```sh
elastic kb saved-objects post-saved-objects-export --type tag --search '<tag-name>' --exclude-export-details \
  | jq -c '.[] | select(.type=="tag") | {id, name: .attributes.name}'
```

## Saved objects route

Verified against Kibana 9.3–9.5 source; preserves panels the Dashboards API cannot. Dashboards are `dashboard` saved
objects: panels live in the `panelsJSON` string attribute, each with a `type`, `panelIndex`, `gridData`, and
`embeddableConfig`. Each panel's references are named `<panelIndex>:<name>`.

**Chart panels** are `type: "vis"` (Kibana 9.4+; panels saved earlier keep `lens`). Legacy and Vega visualizations are
`legacy_vis` (earlier: `visualization`), saved searches `discover_session` (earlier: `search`). A chart is:

- **By reference** — a reference `<panelIndex>:savedObjectRef` to a library object (`lens`, or `visualization` for
  legacy/Vega). Search finds these with `--type lens`.
- **By value** — the full Lens state is stored in the panel's `embeddableConfig.attributes`; there is no library object,
  so only reading the dashboard finds it. An ES|QL chart keeps its query in `attributes.state.query.esql` and in each
  `attributes.state.datasourceStates.textBased.layers.*.query.esql`.

Rules:

- Import with `--overwrite` replaces the whole object and has no concurrency check: always export immediately before
  editing.
- Create without `--overwrite`; an existing id is reported as a conflict instead of overwritten.
- Lens state is internal and version-specific: do not hand-author it from scratch. For a new ES|QL chart on Kibana
  < 9.5, [copy an existing ES|QL chart with a new query](#new-esql-chart-from-an-existing-one), build it in the UI, or
  use the `kibana-vega` skill (ES|QL Vega charts), then add it as a panel.
- Delete via saved objects is stack only; on Serverless use `delete-dashboard` / `delete-visualization`.

**Search** by title (`simple_query_string`), or by tag id:

```bash
elastic kb saved-objects post-saved-objects-export --type dashboard --search '<query>' --exclude-export-details \
  | jq -c '.[] | select(.type=="dashboard") | {id, title: .attributes.title}'
elastic kb saved-objects post-saved-objects-export --type dashboard --has-reference '{"type":"tag","id":"<tag-id>"}' \
  --exclude-export-details | jq -c '.[] | select(.type=="dashboard") | {id, title: .attributes.title}'
```

Use `--type lens` (or `visualization`) to search visualizations.

**Get:**

```bash
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' --exclude-export-details \
  | jq '.[] | select(.type=="dashboard") | {id, title: .attributes.title,
    panels: (.attributes.panelsJSON | fromjson | map({panelIndex, type, gridData})), references}'
```

**List charts** in a dashboard (by-value charts have no `library_id`):

```bash
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' --exclude-export-details \
  | jq -c '.[] | select(.type=="dashboard") | .references as $R | .attributes.panelsJSON | fromjson[]
    | select(.type == "vis" or .type == "lens") | .panelIndex as $i
    | {panelIndex, title: (.embeddableConfig.title // .embeddableConfig.attributes.title),
       library_id: ([$R[] | select(.name == "\($i):savedObjectRef") | .id][0]),
       esql: .embeddableConfig.attributes.state.query.esql}'
```

#### New ES|QL chart from an existing one

Copies a by-value ES|QL chart panel with a new title and query, placed below the existing panels. The new query must
keep the same `FROM` source and output column names as the original: Lens binds each layer's `columns[].fieldName` to
them. Otherwise build the chart in the UI or with `kibana-vega`.

```bash
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' --exclude-export-details \
  | jq -c --arg src '<source-panel-id>' --arg p '<new-panel-id>' --arg title '<title>' --arg q '<esql>' \
  '.[] | select(.type=="dashboard") | (.attributes.panelsJSON | fromjson) as $P
    | ($P[] | select(.panelIndex == $src)) as $s
    | if $s.embeddableConfig.attributes.state.datasourceStates.textBased then . else error("not a by-value ES|QL chart") end
    | ([$P[] | select(.gridData.sectionId == null) | .gridData | .y + .h] | max // 0) as $y
    | ($s | .panelIndex = $p | .gridData += {x:0, y:$y, i:$p} | .embeddableConfig.title = $title
        | .embeddableConfig.attributes.title = $title | .embeddableConfig.attributes.state.query.esql = $q
        | .embeddableConfig.attributes.state.datasourceStates.textBased.layers |= map_values(.query.esql = $q)) as $n
    | .attributes.panelsJSON = ($P + [$n] | tojson)
    | .references += [.references[] | select(.name | startswith("\($src):")) | .name |= "\($p):" + ltrimstr("\($src):")]' > dash.ndjson && \
elastic kb saved-objects post-saved-objects-import --file dash.ndjson --overwrite
```

**Create** an empty dashboard (omit `timeFrom`/`timeTo` and set `timeRestore:false` for no default time range):

```bash
jq -nc --arg id '<dash-id>' --arg title '<title>' '{type:"dashboard", id:$id, attributes:{title:$title, description:"",
  panelsJSON:"[]", optionsJSON:({useMargins:true, syncColors:true, syncTooltips:true, syncCursor:true}|tojson),
  timeRestore:true, timeFrom:"now-7d", timeTo:"now", kibanaSavedObjectMeta:{searchSourceJSON:"{}"}}, references:[]}' > dash.ndjson && \
elastic kb saved-objects post-saved-objects-import --file dash.ndjson
```

**Edit** — export, apply a `jq` filter, re-import:

```bash
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' --exclude-export-details \
  | jq -c '.[] | select(.type=="dashboard") | <filter>' > dash.ndjson && \
elastic kb saved-objects post-saved-objects-import --file dash.ndjson --overwrite
```

`<filter>` per change:

```jq
# Title, description
.attributes.title = "<title>" | .attributes.description = "<text>"

# Default time range
.attributes.timeRestore = true | .attributes.timeFrom = "now-24h" | .attributes.timeTo = "now"

# Replace tags
.references = [.references[] | select(.type != "tag")] + (["<tag-id>"] | map({type:"tag", id:., name:"tag-ref-\(.)"}))

# Move / resize panels (keys are panelIndex values)
({"<panel-id>":{"x":0,"y":0,"w":24,"h":15}}) as $g | .attributes.panelsJSON = (.attributes.panelsJSON | fromjson
  | map(if $g[.panelIndex] then .gridData += $g[.panelIndex] else . end) | tojson)
```

**Add a library panel** by reference. `$t` is the library object's saved-object type (`lens`, `visualization`,
`links`, `search`, or `map`); Kibana maps it to the current panel type on read. `$g` overrides any of `x`, `y`, `w`, `h`;
`y` defaults to below the lowest top-level panel. `<panel-id>` must be unique in the dashboard.

```bash
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' --exclude-export-details \
  | jq -c --arg t '<lens|visualization|links|search|map>' --arg ref '<object-id>' --arg p '<panel-id>' \
    --argjson g '{"w":24,"h":15}' '.[] | select(.type=="dashboard") | (.attributes.panelsJSON | fromjson) as $P
    | ({x:0, w:24, h:15, y:([$P[] | select(.gridData.sectionId == null) | .gridData | .y + .h] | max // 0)} + $g + {i:$p}) as $G
    | .attributes.panelsJSON = ($P + [{type:$t, panelIndex:$p, gridData:$G, embeddableConfig:{}}] | tojson)
    | .references += [{type:$t, id:$ref, name:"\($p):savedObjectRef"}]' > dash.ndjson && \
elastic kb saved-objects post-saved-objects-import --file dash.ndjson --overwrite
```

**Remove a panel** (and its references, including pre-7.13 `panelRefName` ones):

```bash
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' --exclude-export-details \
  | jq -c --arg p '<panel-id>' '.[] | select(.type=="dashboard") | (.attributes.panelsJSON | fromjson) as $P
    | ([$P[] | select(.panelIndex == $p) | .panelRefName // empty]) as $legacy
    | .attributes.panelsJSON = ($P | map(select(.panelIndex != $p)) | tojson)
    | .references |= map(select((.name | startswith("\($p):")) or (.name | IN($legacy[])) | not))' > dash.ndjson && \
elastic kb saved-objects post-saved-objects-import --file dash.ndjson --overwrite
```

**Copy** a dashboard with everything it references to another cluster or space:

```bash
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' \
  --include-references-deep --exclude-export-details | jq -c '.[] | select(.type)' > bundle.ndjson && \
elastic --use-context '<target-context>' kb saved-objects post-saved-objects-import --file bundle.ndjson --overwrite
```

**Duplicate a visualization** under a new id:

```bash
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"lens","id":"<vis-id>"}]' --exclude-export-details \
  | jq -c --arg id '<new-id>' --arg title '<new-title>' '.[] | select(.type=="lens") | .id = $id | .attributes.title = $title' > vis.ndjson && \
elastic kb saved-objects post-saved-objects-import --file vis.ndjson
```

**Delete** (stack only):

```bash
elastic kb saved-objects delete-saved-objects-type-id --type dashboard --id '<dash-id>' --yes
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
| `dashboards` / `visualizations` missing    | Kibana < 9.5 detected                | Use the [Saved objects route](#saved-objects-route)                          |
| Panels missing after `upsert-dashboard`    | API dropped unsupported panels       | Restore from a saved-objects export; edit via saved objects                  |
| Import reports a conflict                  | Id exists, no `--overwrite`          | Pick a new id, or export, edit, and import with `--overwrite`                |
| `jq: error ... fromjson`                   | Export returned no object            | Check the id, type, and the context's space                                  |
| API tag filter returns nothing             | CLI array encoding                   | Use `--input-file` with a string value and `--no-validate`                   |
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
| `POST kbn:/api/saved_objects/_export` | `elastic kb saved-objects post-saved-objects-export --objects '[{"type":"<type>","id":"<id>"}]' --exclude-export-details` | all |
| `POST kbn:/api/saved_objects/_export` | `elastic kb saved-objects post-saved-objects-export --type '<type>' [--search '<q>'] [--has-reference '<json>'] --exclude-export-details` | all |
| `POST kbn:/api/saved_objects/_import` | `elastic kb saved-objects post-saved-objects-import --file '<path.ndjson>' --overwrite`                   | all    |
| `DELETE kbn:/api/saved_objects/{type}/{id}` | `elastic kb saved-objects delete-saved-objects-type-id --type '<type>' --id '<id>' --yes`     | stack  |

\* On older versions use the [Saved objects route](#saved-objects-route).
