# --arg panel: remove the panel and its references (including pre-7.13 panelRefName references).
.[] | select(.type == "dashboard") | (.attributes.panelsJSON | fromjson) as $P
| ([$P[] | select(.panelIndex == $panel) | .panelRefName // empty]) as $legacy
| .attributes.panelsJSON = ($P | map(select(.panelIndex != $panel)) | tojson)
| .references |= map(select((.name | startswith("\($panel):")) or (.name | IN($legacy[])) | not))
