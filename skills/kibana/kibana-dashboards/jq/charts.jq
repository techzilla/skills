# Dashboard export -> chart panels; by-value charts have no library_id.
.[] | select(.type == "dashboard") | .references as $R | .attributes.panelsJSON | fromjson[]
| select(.type == "vis" or .type == "lens") | .panelIndex as $i
| {panelIndex, title: (.embeddableConfig.title // .embeddableConfig.attributes.title),
   library_id: ([$R[] | select(.name == "\($i):savedObjectRef") | .id][0]),
   esql: .embeddableConfig.attributes.state.query.esql}
