# jq -n: --arg id, --arg title; optional --arg from / --arg to (default time range).
($ARGS.named.from // null) as $from
| {type: "dashboard", id: $id, references: [],
   attributes: ({title: $title, description: "", panelsJSON: "[]",
     optionsJSON: ({useMargins: true, syncColors: true, syncTooltips: true, syncCursor: true} | tojson),
     timeRestore: ($from != null), kibanaSavedObjectMeta: {searchSourceJSON: "{}"}}
     + if $from then {timeFrom: $from, timeTo: ($ARGS.named.to // "now")} else {} end)}
