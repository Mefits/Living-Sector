extends RefCounted
## Rust crates/sim_core/src/ai/behavior_tree.rs. Stateful Sequence index; Selector restarts.
## A tree is a Dictionary; action dispatch is a Callable(action, blackboard)->status.
## Conditions are supplied by name at runtime, never serialized as callables.
const RUNNING := "Running"
const SUCCESS := "Success"
const FAILURE := "Failure"

static func sequence(children: Array) -> Dictionary:
	return {"kind": "Sequence", "children": children.duplicate(true), "index": 0}

static func selector(children: Array) -> Dictionary:
	return {"kind": "Selector", "children": children.duplicate(true)}

static func condition(name: String) -> Dictionary:
	return {"kind": "Condition", "name": name}

static func action(value: Variant) -> Dictionary:
	return {"kind": "Action", "value": value}

static func tick(node: Dictionary, blackboard: Dictionary, dispatch: Callable, conditions: Dictionary = {}) -> String:
	match str(node.get("kind", "")):
		"Action":
			if not dispatch.is_valid():
				return FAILURE
			var status: String = str(dispatch.call(node.get("value"), blackboard))
			return status if status in [RUNNING, SUCCESS, FAILURE] else FAILURE
		"Condition":
			var check: Variant = conditions.get(str(node.get("name", "")))
			if check is Callable and check.is_valid() and bool(check.call(blackboard)):
				return SUCCESS
			return FAILURE
		"Sequence":
			var children: Array = node.get("children", [])
			var index: int = int(node.get("index", 0))
			if index >= children.size():
				node["index"] = 0
				return SUCCESS
			if index < 0:
				return FAILURE
			var child: Dictionary = children[index]
			var status := tick(child, blackboard, dispatch, conditions)
			children[index] = child
			node["children"] = children
			if status == SUCCESS:
				index += 1
				if index >= children.size():
					node["index"] = 0
					return SUCCESS
				node["index"] = index
				return RUNNING
			if status == FAILURE:
				node["index"] = 0
			return status
		"Selector":
			var children: Array = node.get("children", [])
			for i in range(children.size()):
				var child: Dictionary = children[i]
				var status := tick(child, blackboard, dispatch, conditions)
				children[i] = child
				node["children"] = children
				if status != FAILURE:
					return status
			return FAILURE
	return FAILURE

static func current_action(node: Dictionary) -> Variant:
	match str(node.get("kind", "")):
		"Action":
			return node.get("value")
		"Condition":
			return node.get("name")
		"Sequence":
			var children: Array = node.get("children", [])
			var index: int = int(node.get("index", 0))
			return current_action(children[index]) if index >= 0 and index < children.size() else null
		"Selector":
			var children: Array = node.get("children", [])
			return current_action(children[0]) if not children.is_empty() else null
	return null

static func reset(node: Dictionary) -> void:
	# Rust resets Sequence descendants; Selector children are not recursively reset.
	if node.get("kind") != "Sequence":
		return
	node["index"] = 0
	var children: Array = node.get("children", [])
	for i in range(children.size()):
		var child: Dictionary = children[i]
		reset(child)
		children[i] = child
	node["children"] = children
