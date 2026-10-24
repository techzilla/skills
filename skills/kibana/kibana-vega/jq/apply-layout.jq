# --slurpfile layout <layout.json>: replace all panels with the layout's visualizations; optional layout title.
# Keeps other attributes and non-panel references (tags).
$layout[0] as $L | .[] | select(.type == "dashboard") | (.attributes.panelsJSON | fromjson) as $P
| ([$P[] | .panelIndex]) as $ids | ([$P[] | .panelRefName // empty]) as $legacy
| .attributes.title = ($L.title // .attributes.title)
| .attributes.panelsJSON = ([$L.panels | to_entries[] | {type: "visualization", panelIndex: "p\(.key)",
    panelRefName: "panel_p\(.key)", gridData: {x: .value.x, y: .value.y, w: .value.w, h: .value.h, i: "p\(.key)"},
    embeddableConfig: {hidePanelTitles: true}}] | tojson)
| .references = ([.references[] | select(.name as $n
      | ($n | IN($legacy[])) or any($ids[]; . as $i | $n | startswith("\($i):")) | not)]
    + [$L.panels | to_entries[] | {type: "visualization", id: .value.visualization, name: "panel_p\(.key)"}])
