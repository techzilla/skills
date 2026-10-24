# jq -n: --arg id, --arg title. Empty dashboard, no default time range.
{type: "dashboard", id: $id, references: [],
 attributes: {title: $title, description: "", panelsJSON: "[]", timeRestore: false,
   optionsJSON: ({useMargins: true, syncColors: true, syncTooltips: true, syncCursor: true} | tojson),
   kibanaSavedObjectMeta: {searchSourceJSON: "{}"}}}
