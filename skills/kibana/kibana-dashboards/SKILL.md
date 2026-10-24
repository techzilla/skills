---
name: kibana-dashboards
description: >
  Create, search, and manage Kibana Dashboards and Lens visualizations. Use when you need to
  find existing dashboards, define dashboards and visualizations declaratively, version control
  them, or automate their deployment.
metadata:
  author: techzilla
  version: 0.7.0
  universal: true
  derived_from: elastic/agent-skills v0.6.0 (Apache-2.0), modified
compatibility: Kibana 9.x stack or Serverless. Written for and verified against `elastic` CLI 0.7.0. The saved objects
  route requires `jq`.
---

# Kibana Dashboards and Lens Visualizations

Search, create, update, and delete Kibana dashboards and standalone Lens visualizations with the `elastic` CLI.

## Setup

Use only the [`elastic` CLI](https://github.com/elastic/cli#configuration) **0.7.0**; never call the HTTP API directly.
If it is missing, tell the user what it is needed for. For a non-default space, use a context whose `kibana.url` ends
in `/s/<space-id>` and pass `--use-context <name>`.

## Step 0: Choose the route (always first)

Run `elastic kb system get-status`. If it fails, stop and show the error. Otherwise read `version.number` and
`version.build_flavor`, then follow exactly one route for the task:

| Situation                                                                      | Route                                     |
| ------------------------------------------------------------------------------ | ----------------------------------------- |
| Stack below 9.5                                                                | [Saved objects](#saved-objects-route)     |
| Exporting, importing, or copying between clusters or spaces (any version)      | [Saved objects](#saved-objects-route)     |
| Editing an existing dashboard that has links panels (any version)              | [Saved objects](#saved-objects-route)     |
| 9.5+ or Serverless, and `get-dashboard` of the target returns `warnings`       | [Saved objects](#saved-objects-route)     |
| 9.5+ or Serverless, otherwise                                                  | [API](#api-route)                         |

Why: CLI 0.7.0 hides the `elastic kb dashboards` / `visualizations` commands below 9.5. On 9.5+, a `get-dashboard`
response with a top-level `warnings` array means panels were dropped or keys stripped, and the 9.5 API strips links
panels' drilldowns (9.4's cannot represent them at all), so writing such a dashboard back with `upsert-dashboard`
deletes content. Never pin a false `version` in the CLI config to unhide commands.

## API route

Only for 9.5+ or Serverless, when Step 0 selected it.

1. **Classify:** a dashboard, a standalone library visualization, or both. If the user gives an id, upsert with it;
   otherwise create and report the generated id.
2. **Choose the dataset** before writing metrics or layers:

   | Intent                               | `data_source`                                                           | Metric / axis                                                    |
   | ------------------------------------ | ----------------------------------------------------------------------- | ---------------------------------------------------------------- |
   | Aggregation on a saved data view     | `{ "type": "data_view_reference", "ref_id": "<id>" }`                   | `{ "type": "primary", "operation": "count" }` (or other op)      |
   | Ad-hoc index pattern                 | `{ "type": "data_view_spec", "index_pattern": "…", "time_field": "…" }` | Same `operation` fields                                          |
   | ES\|QL (requested, or complex logic) | `{ "type": "esql", "query": "…" }`                                      | `{ "type": "primary", "column": "<alias>" }` — never `operation` |

   For ES|QL, aggregate in the query (`STATS count = COUNT()`) and reference the column by name.
3. **Write the body** as JSON to a file. Dashboard bodies are flat: `title` (exact string requested), `panels` (`[]`
   for an empty dashboard — never omit or invent panels), optional `time_range` (persists the default time filter).
   Prefer inline panel `config` over `config.ref_id`.

   ```json
   {
     "title": "Sales Overview",
     "time_range": { "from": "now-7d", "to": "now" },
     "panels": [
       {
         "type": "vis",
         "id": "total-requests",
         "grid": { "x": 0, "y": 0, "w": 12, "h": 6 },
         "config": {
           "title": "Total Requests",
           "type": "metric",
           "data_source": { "type": "esql", "query": "FROM logs* | STATS count = COUNT()" },
           "metrics": [{ "type": "primary", "column": "count" }]
         }
       }
     ]
   }
   ```

   A standalone visualization body is the panel's `config` object alone. For other chart types read
   [Chart Types](references/chart-types-reference.md), [Lens API](references/lens-api-reference.md), and
   [Dashboard API](references/dashboard-api-reference.md); examples are in [assets/](assets/).
4. **Execute, then confirm** with `get-dashboard` / `get-visualization`. Report id and title; never claim success
   without a successful read-back.

**Search:** `--query` is `simple_query_string` on title and description; all words must match.

```sh
elastic kb dashboards search-dashboards --query 'nginx*' --per-page 50 --page 1
elastic kb visualizations search-visualizations --query 'requests*' --per-page 50
```

CLI 0.7.0 mis-encodes array flags (`--tags`, `--excluded-tags`, `--tag-names`, `--excluded-tag-names`), so they match
nothing. Pass one tag id as a string instead; run one call per tag. Tag names need Kibana 9.6+; resolve a name to its
id with `--type tag` in the saved objects route's search.

```sh
echo '{"query":"nginx*","tags":"<tag-id>","per_page":50}' > q.json
elastic kb dashboards search-dashboards --input-file q.json --no-validate
```

| Action                | Command                                                                                     |
| --------------------- | ------------------------------------------------------------------------------------------- |
| Search dashboards     | `elastic kb dashboards search-dashboards [--query '<q>'] [--page N] [--per-page N]`         |
| Get dashboard         | `elastic kb dashboards get-dashboard --id '<id>'`                                           |
| Create dashboard      | `elastic kb dashboards create-dashboard --input-file '<body.json>'`                         |
| Upsert dashboard      | `elastic kb dashboards upsert-dashboard --id '<id>' --input-file '<body.json>'`             |
| Delete dashboard      | `elastic kb dashboards delete-dashboard --id '<id>' --yes`                                  |
| Search visualizations | `elastic kb visualizations search-visualizations [--query '<q>'] [--page N] [--per-page N]` |
| Get visualization     | `elastic kb visualizations get-visualization --id '<id>'`                                   |
| Create visualization  | `elastic kb visualizations create-visualization --input-file '<body.json>'`                 |
| Upsert visualization  | `elastic kb visualizations upsert-visualization --id '<id>' --input-file '<body.json>'`     |
| Delete visualization  | `elastic kb visualizations delete-visualization --id '<id>' --yes`                          |

## Saved objects route

When Step 0 selected it. Never use `elastic kb dashboards` / `visualizations` commands on this route. Filter paths
(`jq/*.jq`) are relative to this skill's directory. Verified against Kibana 9.3–9.5 source.

**Model.** A dashboard is a `dashboard` saved object. Its panels are a JSON string in `attributes.panelsJSON`; each
panel has `type`, `panelIndex`, `gridData` (same grid as [Layout](#layout)), and `embeddableConfig`, and its references
are named `<panelIndex>:<name>`. Panel types (9.4+, earlier name): `vis` (`lens`) is a Lens chart; `legacy_vis`
(`visualization`) a legacy or Vega visualization; `discover_session` (`search`) a saved search; also `links`,
`markdown`, controls. A chart is either:

- **By reference** — reference `<panelIndex>:savedObjectRef` to a library `lens` / `visualization` object.
- **By value** — full Lens state in `embeddableConfig.attributes`, no library object; found only by reading the
  dashboard. An ES|QL chart's query is in `attributes.state.query.esql` and each
  `attributes.state.datasourceStates.textBased.layers.*.query.esql`.

**Rules.**

- Never hand-write Lens state. For a new chart: copy an existing ES|QL chart (`copy-esql-chart`), build it in the UI,
  or use the `kibana-vega` skill; then add it with `add-panel`.
- Export immediately before each edit: import with `--overwrite` replaces the whole object without a concurrency check.
- Create without `--overwrite`, so an existing id is reported as a conflict.
- Delete is stack only; on Serverless use the API route's delete commands.

**Read.**

```bash
# Search by title (simple_query_string); use --type lens|visualization|tag for other objects
elastic kb saved-objects post-saved-objects-export --type dashboard --search '<query>' --exclude-export-details | jq -c -f jq/list.jq
# Search by tag id
elastic kb saved-objects post-saved-objects-export --type dashboard --has-reference '{"type":"tag","id":"<tag-id>"}' \
  --exclude-export-details | jq -c -f jq/list.jq
# Get one dashboard (summary.jq), or list its charts (charts.jq; by-value charts have no library_id)
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' \
  --exclude-export-details | jq -f jq/summary.jq
```

**Edit** — every edit is export → filter → import:

```bash
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' \
  --exclude-export-details | jq -c <args> -f jq/<filter>.jq > dash.ndjson && \
elastic kb saved-objects post-saved-objects-import --file dash.ndjson --overwrite
```

| Change                       | `<filter>`        | `<args>`                                                                                         |
| ---------------------------- | ----------------- | ------------------------------------------------------------------------------------------------ |
| Title, description, time     | `set`             | `--argjson set '{"title":"…","timeRestore":true,"timeFrom":"now-24h","timeTo":"now"}'`           |
| Replace tags                 | `tags`            | `--argjson tags '["<tag-id>"]'`                                                                  |
| Add library panel            | `add-panel`       | `--arg type lens --arg ref '<lens-id>' --arg panel '<new-panel-id>' [--argjson grid '{"w":48}']` |
| Move / resize panels         | `move-panels`     | `--argjson grid '{"<panel-id>":{"x":0,"y":0,"w":24,"h":15}}'`                                    |
| Remove panel                 | `remove-panel`    | `--arg panel '<panel-id>'`                                                                       |
| New ES\|QL chart from one    | `copy-esql-chart` | `--arg src '<panel-id>' --arg panel '<new-panel-id>' --arg title '…' --arg esql '…'`            |

- `add-panel`: `type` is the library object's saved-object type (`lens`, `visualization`, `links`, `search`, `map`).
  Default grid is `x:0, w:24, h:15`, below the lowest panel.
- `copy-esql-chart`: the source must be a by-value ES|QL chart (`charts.jq` shows an `esql` and no `library_id`), and
  the new query must keep its `FROM` source and output column names (Lens binds `columns[].fieldName` to them).

**Create, copy, delete.**

```bash
# New dashboard (omit --arg from/--arg to for no default time range)
jq -nc --arg id '<dash-id>' --arg title '<title>' --arg from now-7d --arg to now -f jq/new-dashboard.jq > dash.ndjson && \
elastic kb saved-objects post-saved-objects-import --file dash.ndjson

# Duplicate a visualization (or any single object) under a new id
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"lens","id":"<vis-id>"}]' --exclude-export-details \
  | jq -c --arg id '<new-id>' --arg title '<new-title>' -f jq/duplicate.jq > vis.ndjson && \
elastic kb saved-objects post-saved-objects-import --file vis.ndjson

# Copy a dashboard and everything it references to another cluster or space
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' \
  --include-references-deep --exclude-export-details | jq -c '.[] | select(.type)' > bundle.ndjson && \
elastic --use-context '<target-context>' kb saved-objects post-saved-objects-import --file bundle.ndjson --overwrite

# Delete (stack only)
elastic kb saved-objects delete-saved-objects-type-id --type dashboard --id '<dash-id>' --yes
```

## Layout

Both routes: 48-column grid; about 20–24 rows fit above the fold, so aim for 8–12 panels there. Stack rows by setting
each `y` to the previous `y + h`; panels in one row share `h`. Use chart titles, not markdown title panels.

| Width   | `w` | `h`   | Use                      |
| ------- | --- | ----- | ------------------------ |
| Full    | 48  | 14–16 | Wide time series, tables |
| Half    | 24  | 10–12 | Primary charts           |
| Quarter | 12  | 5–6   | KPI metrics              |
| Sixth   | 8   | 4–5   | Dense metric rows        |

ES|QL time series (the time picker injects `?_tstart` / `?_tend`; on the API route set `"scale": "temporal"` on the
x-axis):

```esql
FROM logs* | WHERE @timestamp <= ?_tend AND @timestamp > ?_tstart
| STATS count = COUNT() BY BUCKET(@timestamp, 75, ?_tstart, ?_tend)
```

Reference lines: compute them in the query (`| EVAL goal = 15000`) and reference the column.

## Common issues

| Symptom                                 | Fix                                                                         |
| --------------------------------------- | --------------------------------------------------------------------------- |
| `dashboards` / `visualizations` missing | Stack < 9.5: use the [saved objects route](#saved-objects-route)            |
| Panels gone after `upsert-dashboard`    | Restore from a saved-objects export; edit via the saved objects route       |
| API tag filter returns nothing          | String tag via `--input-file` with `--no-validate`                          |
| `must be array` validation error        | Add `--no-validate`                                                         |
| `Pass --yes to confirm`                 | Add `--yes`                                                                 |
| 400 on ES\|QL chart                     | Match `metrics[].column` / layer `column` to the `STATS` aliases            |
| ES\|QL chart saved as data view         | Use `data_source.type: "esql"`                                              |
| XY chart fails                          | Put `data_source` inside each layer                                         |
| Import reports a conflict               | Choose a new id, or export, edit, and import with `--overwrite`             |
| `not a by-value ES\|QL chart`           | Pick a source panel from `charts.jq` with an `esql` and no `library_id`     |
| 404 / empty export                      | Check the id, type, and the context's space                                 |
