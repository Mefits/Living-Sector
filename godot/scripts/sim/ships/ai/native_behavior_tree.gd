extends RefCounted
## N84 — source-faithful native/crates/sim_core/src/ai/behavior_tree.rs.
## A portable, serializable node tree; the caller owns leaf side effects.
## Rust Sequence advances ONE child per tick, even when it succeeded.
## Selector restarts at child zero; a Running leaf suspends traversal.
## Only sequence cursor is persistent. Blackboard scratch is per-tick.
const RUNNING := "running"
const SUCCESS := "success"
const FAILURE := "failure"
const MAX_NODES := 512
const MAX_DEPTH := 32

static func action(spec: Dictionary) -> Dictionary:
    if str(spec.get("kind", "")).is_empty():
        return {}
    return {"kind": "action", "action": spec.duplicate(true)}

static func sequence(children: Array) -> Dictionary:
    return {"kind": "sequence", "index": 0, "children": children.duplicate(true)}

static func selector(children: Array) -> Dictionary:
    return {"kind": "selector", "children": children.duplicate(true)}

## Serializable condition names must refer to authoritative blackboard flags.
## Rust's raw fn pointer cannot be persisted inside a JSON save.
static func condition(name: String) -> Dictionary:
    return {"kind": "condition", "name": name} if not name.is_empty() else {}

static func validate(tree: Dictionary) -> bool:
    var counter: Array[int] = [0]
    return _valid_node(tree, 0, counter)

static func _valid_node(node: Dictionary, depth: int, counter: Array[int]) -> bool:
    if depth > MAX_DEPTH:
        return false
    counter[0] += 1
    if counter[0] > MAX_NODES:
        return false
    var kind: String = str(node.get("kind", ""))
    match kind:
        "action":
            return node.get("action") is Dictionary and not str(node["action"].get("kind", "")).is_empty()
        "condition":
            return node.get("name") is String and not str(node["name"]).is_empty()
        "sequence", "selector":
            if not (node.get("children") is Array):
                return false
            var children: Array = node["children"]
            if kind == "sequence":
                if typeof(node.get("index", null)) != TYPE_INT:
                    return false
                if int(node["index"]) < 0 or int(node["index"]) > children.size():
                    return false
            for child in children:
                if not (child is Dictionary) or not _valid_node(child, depth + 1, counter):
                    return false
            return true
    return false

static func current_action(tree: Dictionary) -> String:
    if not validate(tree):
        return ""
    return _current(tree)

static func _current(node: Dictionary) -> String:
    var kind: String = str(node["kind"])
    match kind:
        "action":
            return str(node["action"].get("kind", ""))
        "condition":
            return str(node["name"])
        "sequence":
            var i: int = int(node["index"])
            var children: Array = node["children"]
            return _current(children[i]) if i < children.size() else ""
        "selector":
            var children: Array = node["children"]
            return _current(children[0]) if not children.is_empty() else ""
    return ""

static func reset(tree: Dictionary) -> Dictionary:
    if not validate(tree):
        return {}
    return _reset_node(tree)

static func _reset_node(node: Dictionary) -> Dictionary:
    var updated: Dictionary = node.duplicate(true)
    if str(updated["kind"]) == "sequence":
        updated["index"] = 0
        for i in range((updated["children"] as Array).size()):
            updated["children"][i] = _reset_node(updated["children"][i])
    return updated

## dispatch(action_spec, blackboard) must RETURN a dictionary with
## status=success|failure|running. It may return a list of N146 command
## INTENTS, which are never applied here. A missing/invalid status FAILS.
## Blackboard is scratch for THIS tick, not serialized into the tree.
static func tick(tree: Dictionary, dispatch: Callable,
        blackboard: Dictionary = {}) -> Dictionary:
    if not validate(tree) or not dispatch.is_valid():
        return {"ok": false, "reason": "invalid_native_bt_or_dispatch"}
    var result: Dictionary = _tick_node(tree, dispatch, blackboard)
    return {"ok": true, "status": result["status"],
        "tree": result["tree"], "commands": result["commands"],
        "blackboard": blackboard.duplicate(true)}

static func _tick_node(node: Dictionary, dispatch: Callable,
        bb: Dictionary) -> Dictionary:
    var updated: Dictionary = node.duplicate(true)
    var kind: String = str(updated["kind"])
    match kind:
        "action":
            var applied: Variant = dispatch.call(updated["action"].duplicate(true), bb)
            if not (applied is Dictionary):
                return _result(FAILURE, updated)
            var status: String = str(applied.get("status", FAILURE))
            if status not in [SUCCESS, RUNNING, FAILURE]:
                return _result(FAILURE, updated)
            var commands: Variant = applied.get("commands", [])
            if not (commands is Array):
                return _result(FAILURE, updated)
            return _result(status, updated, commands)
        "condition":
            # Rust ConditionFn -> Bool. The P2 serializable equivalent is
            # a typed boolean explicitly supplied by the observing caller.
            var v: Variant = bb.get(str(updated["name"]), false)
            return _result(SUCCESS if v is bool and v else FAILURE, updated)
        "sequence":
            var children: Array = updated["children"]
            var idx: int = int(updated["index"])
            if idx >= children.size():
                updated["index"] = 0
                return _result(SUCCESS, updated)
            var result: Dictionary = _tick_node(children[idx], dispatch, bb)
            children[idx] = result["tree"]
            if result["status"] == SUCCESS:
                idx += 1
                updated["index"] = 0 if idx >= children.size() else idx
                return _result(SUCCESS if idx >= children.size() else RUNNING,
                    updated, result["commands"])
            if result["status"] == FAILURE:
                updated["index"] = 0
            return _result(result["status"], updated, result["commands"])
        "selector":
            var children: Array = updated["children"]
            for i in range(children.size()):
                var result: Dictionary = _tick_node(children[i], dispatch, bb)
                children[i] = result["tree"]
                if result["status"] != FAILURE:
                    return _result(result["status"], updated, result["commands"])
            return _result(FAILURE, updated)
    return _result(FAILURE, updated)

static func _result(status: String, tree: Dictionary,
        commands: Array = []) -> Dictionary:
    return {"status": status, "tree": tree,
        "commands": commands.duplicate(true)}
