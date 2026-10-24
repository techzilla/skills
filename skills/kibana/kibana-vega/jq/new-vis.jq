# jq -n: --arg id, --arg title, --rawfile spec <spec.json>. Fails if the spec is not valid JSON.
($spec | fromjson) as $_
| {type: "visualization", id: $id, references: [],
   attributes: {title: $title, description: "", uiStateJSON: "{}", kibanaSavedObjectMeta: {searchSourceJSON: "{}"},
     visState: ({title: $title, type: "vega", params: {spec: $spec}, aggs: []} | tojson)}}
