# --argjson grid '{"<panel-id>": {"x":..,"y":..,"w":..,"h":..}, ...}': set position/size of listed panels.
.[] | select(.type == "dashboard")
| .attributes.panelsJSON = (.attributes.panelsJSON | fromjson
    | map(if $grid[.panelIndex] then .gridData += $grid[.panelIndex] else . end) | tojson)
