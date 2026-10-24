# Visualization export -> Vega visualizations only.
.[] | select(.type == "visualization" and (.attributes.visState | fromjson | .type) == "vega") | {id, title: .attributes.title}
