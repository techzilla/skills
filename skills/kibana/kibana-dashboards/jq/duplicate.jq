# --arg id (new id), --arg title: copy one exported object (e.g. a lens visualization).
.[] | select(.type) | .id = $id | .attributes.title = $title
