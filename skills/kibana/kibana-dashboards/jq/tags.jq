# --argjson tags '["<tag-id>", ...]': replace the dashboard's tags.
.[] | select(.type == "dashboard")
| .references = [.references[] | select(.type != "tag")] + ($tags | map({type: "tag", id: ., name: "tag-ref-\(.)"}))
