# --argjson set '{...}': merge into dashboard attributes (title, description, timeRestore, timeFrom, timeTo).
.[] | select(.type == "dashboard") | .attributes += $set
