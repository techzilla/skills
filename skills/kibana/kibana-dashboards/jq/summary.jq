# Dashboard export -> panels and references.
.[] | select(.type == "dashboard")
| {id, title: .attributes.title,
   panels: (.attributes.panelsJSON | fromjson | map({panelIndex, type, gridData})), references}
