class_name NeocortexUiUtils
extends RefCounted

## Lookups the chat UI controllers use to find their parts when they are not assigned.

## The first descendant of `root` (depth first) that is an instance of `type`.
static func find_descendant(root: Node, type: Variant) -> Node:
	if root == null:
		return null
	for child in root.get_children():
		if is_instance_of(child, type):
			return child
		var nested := find_descendant(child, type)
		if nested != null:
			return nested
	return null
