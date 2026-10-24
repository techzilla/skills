# --arg vis (visualization id), --arg panel (new unique panel id); optional --argjson grid '{"x":..,"y":..,"w":..,"h":..}'.
# Default grid: x 0, w 48, h 15, below the lowest panel.
.[] | select(.type == "dashboard") | (.attributes.panelsJSON | fromjson) as $P
| ({x: 0, w: 48, h: 15, y: ([$P[].gridData | .y + .h] | max // 0)} + ($ARGS.named.grid // {}) + {i: $panel}) as $G
| .attributes.panelsJSON = ($P + [{type: "visualization", panelIndex: $panel, panelRefName: "panel_\($panel)",
    gridData: $G, embeddableConfig: {hidePanelTitles: true}}] | tojson)
| .references += [{type: "visualization", id: $vis, name: "panel_\($panel)"}]
