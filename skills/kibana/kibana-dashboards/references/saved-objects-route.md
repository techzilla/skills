# Saved Objects Route

Use on Kibana stack < 9.5 (CLI 0.7.0 hides the Dashboards/Visualizations commands there), or on any version to edit a
dashboard the Dashboards API cannot round-trip. Verified against Kibana 9.3–9.5 source and CLI 0.7.0. Requires `jq`.
Filter paths (`jq/*.jq`) are relative to this skill's directory.

## Model

A dashboard is a `dashboard` saved object. Its panels are a JSON string in `attributes.panelsJSON`; each panel has
`type`, `panelIndex`, `gridData`, and `embeddableConfig`, and its references are named `<panelIndex>:<name>`.

| Panel `type` (9.4+, earlier name)          | Content                                                                    |
| ------------------------------------------ | -------------------------------------------------------------------------- |
| `vis` (`lens`)                             | Lens chart                                                                 |
| `legacy_vis` (`visualization`)             | Legacy or Vega visualization                                               |
| `discover_session` (`search`)              | Saved search                                                               |
| `links`, `markdown`, controls, …           | Other panels                                                               |

A chart is **by reference** (reference `<panelIndex>:savedObjectRef` to a library `lens`/`visualization` object, found
by `--type lens` search) or **by value** (full Lens state in `embeddableConfig.attributes`; found only by reading the
dashboard). An ES|QL chart's query is in `attributes.state.query.esql` and each
`attributes.state.datasourceStates.textBased.layers.*.query.esql`.

## Rules

- Never hand-write Lens state. For a new chart: copy an existing ES|QL chart (`copy-esql-chart.jq`), build it in the
  UI, or use the `kibana-vega` skill; then add it with `add-panel.jq`.
- Import with `--overwrite` replaces the whole object without a concurrency check: export immediately before each edit.
- Create without `--overwrite`, so an existing id is reported as a conflict.
- Delete is stack only; on Serverless use `delete-dashboard` / `delete-visualization`.

## Read

```bash
# Search by title (simple_query_string); --type lens|visualization|tag for other objects
elastic kb saved-objects post-saved-objects-export --type dashboard --search '<query>' --exclude-export-details | jq -c -f jq/list.jq
# Search by tag id
elastic kb saved-objects post-saved-objects-export --type dashboard --has-reference '{"type":"tag","id":"<tag-id>"}' \
  --exclude-export-details | jq -c -f jq/list.jq
# Get one dashboard (summary.jq), or list its charts (charts.jq)
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' \
  --exclude-export-details | jq -f jq/summary.jq
```

## Edit a dashboard

Every edit is export → filter → import:

```bash
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' \
  --exclude-export-details | jq -c <args> -f jq/<filter>.jq > dash.ndjson && \
elastic kb saved-objects post-saved-objects-import --file dash.ndjson --overwrite
```

| Change                       | `<filter>`        | `<args>`                                                                                       |
| ---------------------------- | ----------------- | ---------------------------------------------------------------------------------------------- |
| Title, description, time     | `set`             | `--argjson set '{"title":"…","timeRestore":true,"timeFrom":"now-24h","timeTo":"now"}'`         |
| Replace tags                 | `tags`            | `--argjson tags '["<tag-id>"]'`                                                                |
| Add library panel            | `add-panel`       | `--arg type lens --arg ref '<lens-id>' --arg panel '<new-panel-id>' [--argjson grid '{"w":48}']` |
| Move / resize panels         | `move-panels`     | `--argjson grid '{"<panel-id>":{"x":0,"y":0,"w":24,"h":15}}'`                                  |
| Remove panel                 | `remove-panel`    | `--arg panel '<panel-id>'`                                                                     |
| New ES\|QL chart from one    | `copy-esql-chart` | `--arg src '<panel-id>' --arg panel '<new-panel-id>' --arg title '…' --arg esql '…'`          |

- `add-panel`: `type` is the library object's saved-object type (`lens`, `visualization`, `links`, `search`, `map`).
  Default grid is `x:0, w:24, h:15`, below the lowest panel.
- `copy-esql-chart`: the source must be a by-value ES|QL chart, and the new query must keep its `FROM` source and output
  column names (Lens binds `columns[].fieldName` to them).

## Create, copy, delete

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
