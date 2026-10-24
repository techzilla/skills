---
name: kibana-dashboards
description: >
  Create, search, and manage Kibana Dashboards and Lens visualizations. Use when you need to
  find existing dashboards, define dashboards and visualizations declaratively, version control
  them, or automate their deployment.
metadata:
  author: techzilla
  version: 0.6.0
  universal: true
  derived_from: elastic/agent-skills v0.6.0 (Apache-2.0), modified
compatibility: Kibana 9.x stack or Serverless. Written for and verified against `elastic` CLI 0.7.0. The saved objects
  route (Kibana < 9.5) requires `jq`.
---

# Kibana Dashboards and Lens Visualizations

Search, create, update, and delete Kibana dashboards and standalone Lens visualizations with the `elastic` CLI.

## Setup

Use only the [`elastic` CLI](https://github.com/elastic/cli#configuration) **0.7.0**; never call the HTTP API directly.
If it is missing, tell the user what it is needed for. For a non-default space, use a context whose `kibana.url` ends
in `/s/<space-id>` and pass `--use-context <name>`.

Run `elastic kb system get-status`. If it fails, stop and show the error. Then choose a route:

| Kibana             | Route                                                                     |
| ------------------ | ------------------------------------------------------------------------- |
| 9.5+ or Serverless | Dashboards/Visualizations API (this file)                                 |
| stack < 9.5        | [Saved objects route](references/saved-objects-route.md) for everything   |

Also use the saved objects route to edit a dashboard that the API cannot round-trip: one whose `get-dashboard`
response has a top-level `warnings` array (dropped panels, stripped keys), or that has links panels (9.4 cannot
represent them; 9.5 strips their drilldowns). Writing such a dashboard with `upsert-dashboard` deletes content.

## Workflow (9.5+ or Serverless)

1. **Classify:** a dashboard, a standalone library visualization, or both. If the user gives an id, upsert (`PUT`)
   with it; otherwise create (`POST`) and report the generated id.
2. **Choose the dataset** before writing metrics or layers:

   | Intent                                | `data_source`                                                     | Metric / axis                                               |
   | ------------------------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------- |
   | Aggregation on a saved data view      | `{ "type": "data_view_reference", "ref_id": "<id>" }`             | `{ "type": "primary", "operation": "count" }` (or other op) |
   | Ad-hoc index pattern                  | `{ "type": "data_view_spec", "index_pattern": "…", "time_field": "…" }` | Same `operation` fields                               |
   | ES\|QL (requested, or complex logic)  | `{ "type": "esql", "query": "…" }`                                | `{ "type": "primary", "column": "<alias>" }` — never `operation` |

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

## Search

`--query` is `simple_query_string` on title and description; all words must match.

```sh
elastic kb dashboards search-dashboards --query 'nginx*' --per-page 50 --page 1
elastic kb visualizations search-visualizations --query 'requests*' --per-page 50
```

CLI 0.7.0 mis-encodes array flags (`--tags`, `--excluded-tags`, `--tag-names`, `--excluded-tag-names`), so they match
nothing. Pass one tag id as a string instead; run one call per tag:

```sh
echo '{"query":"nginx*","tags":"<tag-id>","per_page":50}' > q.json
elastic kb dashboards search-dashboards --input-file q.json --no-validate
```

Tag names need Kibana 9.6+; resolve a name to its id with the saved objects route's tag search.

## Layout

48-column grid; about 20–24 rows fit above the fold, so aim for 8–12 panels there. Stack rows by setting each `y` to the
previous `y + h`; panels in one row share `h`. Use chart titles, not markdown title panels.

| Width   | `w` | `h`   | Use                      |
| ------- | --- | ----- | ------------------------ |
| Full    | 48  | 14–16 | Wide time series, tables |
| Half    | 24  | 10–12 | Primary charts           |
| Quarter | 12  | 5–6   | KPI metrics              |
| Sixth   | 8   | 4–5   | Dense metric rows        |

ES|QL time series (the time picker injects `?_tstart` / `?_tend`; set `"scale": "temporal"` on the x-axis):

```esql
FROM logs* | WHERE @timestamp <= ?_tend AND @timestamp > ?_tstart
| STATS count = COUNT() BY BUCKET(@timestamp, 75, ?_tstart, ?_tend)
```

Reference lines: compute them in the query (`| EVAL goal = 15000`) and reference the column.

## Common issues

| Symptom                                 | Fix                                                                            |
| --------------------------------------- | ------------------------------------------------------------------------------ |
| `dashboards` / `visualizations` missing | Kibana < 9.5: use the [saved objects route](references/saved-objects-route.md) |
| Panels gone after `upsert-dashboard`    | Restore from a saved-objects export; edit via the saved objects route          |
| API tag filter returns nothing          | String tag via `--input-file` with `--no-validate`                             |
| `must be array` validation error        | Add `--no-validate`                                                            |
| `Pass --yes to confirm`                 | Add `--yes`                                                                    |
| 400 on ES\|QL chart                     | Match `metrics[].column` / layer `column` to the `STATS` aliases               |
| ES\|QL chart saved as data view         | Use `data_source.type: "esql"`                                                 |
| XY chart fails                          | Put `data_source` inside each layer                                            |
| 404 after write                         | Check the id and the context's space                                           |

## Operations (9.5+ or Serverless)

| Action                  | Command                                                                                  |
| ----------------------- | ---------------------------------------------------------------------------------------- |
| Status                  | `elastic kb system get-status`                                                           |
| Search dashboards       | `elastic kb dashboards search-dashboards [--query '<q>'] [--page N] [--per-page N]`      |
| Get dashboard           | `elastic kb dashboards get-dashboard --id '<id>'`                                        |
| Create dashboard        | `elastic kb dashboards create-dashboard --input-file '<body.json>'`                      |
| Upsert dashboard        | `elastic kb dashboards upsert-dashboard --id '<id>' --input-file '<body.json>'`          |
| Delete dashboard        | `elastic kb dashboards delete-dashboard --id '<id>' --yes`                               |
| Search visualizations   | `elastic kb visualizations search-visualizations [--query '<q>'] [--page N] [--per-page N]` |
| Get visualization       | `elastic kb visualizations get-visualization --id '<id>'`                                |
| Create visualization    | `elastic kb visualizations create-visualization --input-file '<body.json>'`              |
| Upsert visualization    | `elastic kb visualizations upsert-visualization --id '<id>' --input-file '<body.json>'`  |
| Delete visualization    | `elastic kb visualizations delete-visualization --id '<id>' --yes`                       |
| Export, import, copy    | [Saved objects route](references/saved-objects-route.md)                                 |
