# --arg type (library saved-object type: lens|visualization|links|search|map), --arg ref (its id),
# --arg panel (new unique panel id); optional --argjson grid '{"x":..,"y":..,"w":..,"h":..}'.
# Default grid: x 0, w 24, h 15, below the lowest top-level panel.
.[] | select(.type == "dashboard") | (.attributes.panelsJSON | fromjson) as $P
| ({x: 0, w: 24, h: 15, y: ([$P[] | select(.gridData.sectionId == null) | .gridData | .y + .h] | max // 0)}
   + ($ARGS.named.grid // {}) + {i: $panel}) as $G
| .attributes.panelsJSON = ($P + [{type: $type, panelIndex: $panel, gridData: $G, embeddableConfig: {}}] | tojson)
| .references += [{type: $type, id: $ref, name: "\($panel):savedObjectRef"}]
