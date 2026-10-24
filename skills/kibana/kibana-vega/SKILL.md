---
name: kibana-vega
description: >
  Create Vega and Vega-Lite visualizations with ES|QL data sources in Kibana. Use
  when building custom charts, dashboards, or programmatic panel layouts beyond standard
  Lens charts.
metadata:
  author: techzilla
  version: 0.2.0
  derived_from: elastic/agent-skills v0.4.0 (Apache-2.0), modified
compatibility: Kibana 9.4+ or Serverless. Written for and verified against `elastic` CLI 0.7.0. Requires `jq`.
---

# Kibana Vega

Create and manage Kibana dashboards and Vega visualizations with ES|QL data sources.

## Overview

Vega is a declarative visualization grammar for creating custom charts in Kibana. Combined with ES|QL queries, it
enables highly customized visualizations beyond standard Kibana charts.

**Version requirement:** This skill strictly supports **ES|QL data sources** and requires **Serverless Kibana or 9.4+**.

Vega visualizations are legacy `visualization` saved objects; the Dashboards and Visualizations APIs do not support
them. All operations use the saved objects API through the `elastic` CLI 0.7.0, with `jq` building the objects. The
saved-objects commands are not version-gated, so no `version` pin is needed.

## Quick Start

### Environment Configuration

Connection comes from the [`elastic` CLI](https://github.com/elastic/cli#configuration) context. Run
`elastic kb system get-status` to verify it. If it fails, tell the user to configure a context with a `kibana` block,
then stop. Do not guess credentials or call the HTTP API directly. For a non-default space, use a context whose
`kibana.url` ends in `/s/<space-id>` and select it with `--use-context <name>`.

### Visualizations

**Create or update** (same command; `--overwrite` replaces an existing id). Choose a stable, unique `id`.

```bash
jq -nc --arg id '<vis-id>' --arg title '<title>' --rawfile spec spec.json \
  '($spec|fromjson) as $_ | {type:"visualization", id:$id, attributes:{title:$title, description:"",
   visState:({title:$title, type:"vega", params:{spec:$spec}, aggs:[]}|tojson), uiStateJSON:"{}",
   kibanaSavedObjectMeta:{searchSourceJSON:"{}"}}, references:[]}' > vis.ndjson
elastic kb saved-objects post-saved-objects-import --file vis.ndjson --overwrite
```

`jq` fails on invalid JSON in `spec.json`; fix the spec rather than bypassing the check.

**Get spec** for review or modification:

```bash
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"visualization","id":"<vis-id>"}]' \
  --exclude-export-details | jq -r '.[] | select(.type=="visualization") | .attributes.visState | fromjson | .params.spec' > spec.json
```

**Search** (`--search` uses `simple_query_string` on titles):

```bash
elastic kb saved-objects post-saved-objects-export --type visualization --search '<query>' --exclude-export-details \
  | jq -c '.[] | select(.type=="visualization" and (.attributes.visState | fromjson | .type) == "vega") | {id, title: .attributes.title}'
```

### Dashboards

**Create** an empty dashboard:

```bash
jq -nc --arg id '<dash-id>' --arg title '<title>' '{type:"dashboard", id:$id, attributes:{title:$title, description:"",
  panelsJSON:"[]", optionsJSON:({useMargins:true, syncColors:true, syncTooltips:true, syncCursor:true}|tojson),
  timeRestore:false, kibanaSavedObjectMeta:{searchSourceJSON:"{}"}}, references:[]}' > dash.ndjson
elastic kb saved-objects post-saved-objects-import --file dash.ndjson --overwrite
```

**Search** dashboards: `post-saved-objects-export --type dashboard --search '<query>' --exclude-export-details`, then
`jq -c '.[] | select(.type=="dashboard") | {id, title: .attributes.title}'`.

**Add a panel.** `$g` sets any of `x`, `y`, `w`, `h`; omitted values default to `x:0, w:48, h:15` and `y` below the
lowest panel. `<panel-id>` must be unique within the dashboard.

```bash
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' --exclude-export-details \
  | jq -c --arg vis '<vis-id>' --arg p '<panel-id>' --argjson g '{"x":0,"y":0,"w":24,"h":10}' '.[] | select(.type=="dashboard")
    | (.attributes.panelsJSON | fromjson) as $P
    | ({x:0, w:48, h:15, y:([$P[].gridData | .y + .h] | max // 0)} + $g + {i:$p}) as $G
    | .attributes.panelsJSON = ($P + [{type:"visualization", panelIndex:$p, panelRefName:"panel_\($p)", gridData:$G,
        embeddableConfig:{hidePanelTitles:true}}] | tojson)
    | .references += [{type:"visualization", id:$vis, name:"panel_\($p)"}]' > dash.ndjson
elastic kb saved-objects post-saved-objects-import --file dash.ndjson --overwrite
```

**Apply a layout.** Replaces all panels and panel references; keeps other attributes and non-panel references (tags).
`title` is optional.

```bash
elastic kb saved-objects post-saved-objects-export --objects '[{"type":"dashboard","id":"<dash-id>"}]' --exclude-export-details \
  | jq -c --slurpfile l layout.json '$l[0] as $L | .[] | select(.type=="dashboard")
    | .attributes.title = ($L.title // .attributes.title)
    | .attributes.panelsJSON = ([$L.panels | to_entries[] | {type:"visualization", panelIndex:"p\(.key)",
        panelRefName:"panel_p\(.key)", gridData:{x:.value.x, y:.value.y, w:.value.w, h:.value.h, i:"p\(.key)"},
        embeddableConfig:{hidePanelTitles:true}}] | tojson)
    | .references = ([.references[] | select(.name | contains("panel_") | not)]
        + [$L.panels | to_entries[] | {type:"visualization", id:.value.visualization, name:"panel_p\(.key)"}])' > dash.ndjson
elastic kb saved-objects post-saved-objects-import --file dash.ndjson --overwrite
```

**Never** edit a dashboard containing Vega panels with `elastic kb dashboards upsert-dashboard`: the Dashboards API
drops unsupported panels, so the write deletes them.

### Minimal Vega Spec with ES|QL

**IMPORTANT**: Always use proper JSON format (not HJSON with triple quotes) to avoid parse errors.

```json
{
  "$schema": "https://vega.github.io/schema/vega-lite/v6.json",
  "title": "My Chart",
  "autosize": { "type": "fit", "contains": "padding" },

  "config": {
    "axis": { "domainColor": "#444", "tickColor": "#444" },
    "view": { "stroke": null }
  },

  "data": {
    "url": {
      "%type%": "esql",
      "query": "FROM logs-* | STATS count = COUNT() BY status | RENAME status AS category"
    }
  },

  "mark": { "type": "bar", "color": "#6092C0" },
  "encoding": {
    "x": { "field": "category", "type": "nominal" },
    "y": { "field": "count", "type": "quantitative" }
  }
}
```

### ES|QL Data Source Options

| Property                    | Description                                |
| --------------------------- | ------------------------------------------ |
| `%type%: "esql"`            | Required. Use the ES\|QL parser            |
| `%context%: true`           | Apply dashboard filters                    |
| `%timefield%: "@timestamp"` | Enable time range with `?_tstart`/`?_tend` |

## Dashboard Layout Design

### Grid System

Kibana dashboards use a **48-column grid**:

| Width   | Columns | Use Case                         |
| ------- | ------- | -------------------------------- |
| Full    | 48      | Timelines, heatmaps, wide charts |
| Half    | 24      | Side-by-side comparisons         |
| Third   | 16      | Three-column layouts             |
| Quarter | 12      | KPI metrics, small summaries     |

### Above the Fold (Critical)

**Primary information must be visible without scrolling.**

| Resolution | Visible Height | Layout Budget              |
| ---------- | -------------- | -------------------------- |
| 1080p      | ~30 units      | 2 rows: h:10 + h:12        |
| 1440p      | ~40 units      | 3 rows: h:12 + h:12 + h:12 |

**Height guidelines:**

- `h: 10` — Compact bar charts (≤7 items), fits above fold
- `h: 12-13` — Standard charts, timelines
- `h: 15+` — Detailed views, use below fold

### Layout Pattern: Operational Dashboard

```text
┌───────────────────────┬───────────────────────┐  y:0
│  Current State A      │  Current State B      │  h:10 (compact)
├───────────────────────┴───────────────────────┤  y:10
│         Primary Timeline                      │  h:12 (main trend)
├ ─ ─ ─ ─ ─ ─ ─ FOLD ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┤  y:22 (1080p fold)
│         Secondary Timeline                    │  h:12 (below fold OK)
├───────────────────────┬───────────────────────┤  y:34
│  Complementary 1      │  Complementary 2      │  h:10
└───────────────────────┴───────────────────────┘
```

As `layout.json` for **Apply a layout**:

```json
{
  "title": "My Dashboard",
  "panels": [
    { "visualization": "<vis-id-1>", "x": 0, "y": 0, "w": 24, "h": 10 },
    { "visualization": "<vis-id-2>", "x": 24, "y": 0, "w": 24, "h": 10 },
    { "visualization": "<vis-id-3>", "x": 0, "y": 10, "w": 48, "h": 12 },
    { "visualization": "<vis-id-4>", "x": 0, "y": 22, "w": 48, "h": 12 }
  ]
}
```

### Design Checklist

1. **Above the fold**: Primary info in top ~22 height units (1080p)
2. **Compact heights**: Use h:10 for bar charts with ≤7 items
3. **Prioritize**: Most important info top-left
4. **Group**: Related charts side-by-side for comparison
5. **Timelines**: Full width (w:48), h:12 for compact
6. **Below fold**: Complementary/detailed panels OK to scroll

## Guidelines

1. **Use JSON, not HJSON triple-quotes** — `'''` multi-line strings cause parse errors in Kibana; use single-line
   queries with escaped quotes `\"`
2. **Rename dotted fields** — `room.name` breaks Vega (interpreted as nested path); use ES|QL `RENAME room.name AS room`
3. **Don't set width/height** — use `autosize: { type: fit, contains: padding }` (omit it for discrete-axis charts)
4. **Set labelLimit on axes** — horizontal bar chart labels truncate; use `axis: { "labelLimit": 150 }`
5. **Sort bars by value** — pre-sort in ES|QL with `SORT field DESC` and use `sort: null` in encoding (preserves data
   order); avoid `sort: "-x"` in layered specs (bar + text labels) as it causes "conflicting sort properties" warnings
6. **Time axis: no rotated labels** — use `axis: { "labelAngle": 0, "tickCount": 8 }`, let Vega auto-format dates
7. **Descriptive titles replace axis titles** — good title/subtitle makes axis titles redundant; use `title: null` on
   axes
8. **Use color sparingly** — color is a precious visual attribute; use a single default color (`#6092C0`) for bar charts
   where position already encodes value; reserve color encoding for categorical distinction (e.g., multiple lines in a
   time series)
9. **Dark theme compatibility** — always include config to avoid bright white borders:

   ```json
   "config": {
     "axis": { "domainColor": "#444", "tickColor": "#444" },
     "view": { "stroke": null }
   }
   ```

## Operations

Verified against CLI 0.7.0.

| Action                       | `elastic` CLI command                                                                                      | Kibana        |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------- | ------------- |
| Test connection              | `elastic kb system get-status`                                                                             | all           |
| Create / update object       | `elastic kb saved-objects post-saved-objects-import --file '<file.ndjson>' --overwrite`                    | all           |
| Get object                   | `elastic kb saved-objects post-saved-objects-export --objects '[{"type":"<type>","id":"<id>"}]' --exclude-export-details` | all |
| Search objects               | `elastic kb saved-objects post-saved-objects-export --type '<type>' --search '<query>' --exclude-export-details` | all      |
| Delete object                | `elastic kb saved-objects delete-saved-objects-type-id --type '<type>' --id '<id>' --yes`                  | stack only    |

Export output is a JSON array. On Serverless, delete is unavailable; tell the user to remove the object in **Stack
Management > Saved Objects**.

## Full Documentation

- [Dashboard Layout Reference](references/dashboard-layout-reference.md) — Grid system, layout patterns, design best
  practices
- [Vega-Lite Reference](references/vega-lite-reference.md) — Complete Vega-Lite grammar, chart patterns, best practices
- [ES|QL in Vega Reference](references/vega-esql-reference.md) — ES|QL data source configuration, time filtering,
  parameters
- [Example Specs](examples/) — Ready-to-use JSON chart specs: `top-n-bar.json`, `time-series-line.json`, `heatmap.json`

## Common Issues

| Error                                  | Solution                                                                                             |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `jq: error ... fromjson`               | `spec.json` is not valid JSON; fix it (no HJSON, comments, or `'''`)                                 |
| "End of input while parsing an object" | Don't use HJSON `'''` triple-quotes; use JSON with single-line queries                               |
| Labels show "undefined"                | Rename dotted fields: `RENAME room.name AS room`                                                     |
| Bars invisible / not rendering         | Remove complex `scale.domain`, use simpler color schemes                                             |
| Y-axis labels truncated                | Add `axis: { "labelLimit": 150 }` to encoding                                                        |
| Panels stacked vertically              | Set `x`/`y`/`w`/`h` in `$g` or `layout.json`                                                         |
| "width/height ignored"                 | Remove dimensions, use `autosize`                                                                    |
| Bright white borders on dark theme     | Add `config: { "view": { "stroke": null }, "axis": { "domainColor": "#444", "tickColor": "#444" } }` |
| "401 Unauthorized"                     | Check the CLI context's `kibana.auth`                                                                |
| "conflicting sort properties"          | Don't use `sort: "-x"` in layered specs; pre-sort in ES\|QL and use `sort: null`                     |
| Vega panels vanished                   | Dashboard was written via the Dashboards API; re-apply the layout via saved objects                  |
| Empty export / "404 Not Found"         | Verify dashboard/visualization id and the context's space                                            |
