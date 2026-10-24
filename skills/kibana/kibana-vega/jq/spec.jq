# Visualization export -> its Vega spec text (use jq -r).
.[] | select(.type == "visualization") | .attributes.visState | fromjson | .params.spec
