# --arg src (by-value ES|QL chart panel id), --arg panel (new panel id), --arg title, --arg esql.
# New query must keep the source's FROM and output column names. Placed below existing panels.
.[] | select(.type == "dashboard") | (.attributes.panelsJSON | fromjson) as $P
| ($P[] | select(.panelIndex == $src)) as $s
| if $s.embeddableConfig.attributes.state.datasourceStates.textBased then . else error("not a by-value ES|QL chart") end
| ([$P[] | select(.gridData.sectionId == null) | .gridData | .y + .h] | max // 0) as $y
| ($s | .panelIndex = $panel | .gridData += {x: 0, y: $y, i: $panel} | .embeddableConfig.title = $title
    | .embeddableConfig.attributes.title = $title | .embeddableConfig.attributes.state.query.esql = $esql
    | .embeddableConfig.attributes.state.datasourceStates.textBased.layers |= map_values(.query.esql = $esql)) as $n
| .attributes.panelsJSON = ($P + [$n] | tojson)
| .references += [.references[] | select(.name | startswith("\($src):")) | .name |= "\($panel):" + ltrimstr("\($src):")]
