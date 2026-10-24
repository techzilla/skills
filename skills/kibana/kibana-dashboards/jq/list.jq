# Export output -> one line per object.
.[] | select(.type) | {id, type, title: (.attributes.title // .attributes.name)}
