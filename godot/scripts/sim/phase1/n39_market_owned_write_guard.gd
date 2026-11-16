extends RefCounted
## N39 II-B shadow guard for N150 observation-only market writes.
## Does not replace Schema.validate or authorize a World/N9 commit.
## The caller supplies detached before/after market dictionaries. No copies
## of the growing receipts, ships, or unrelated World domains are needed.
const Observation = preload("res://scripts/sim/phase1/n39_market_observation_validator.gd")

static func validate_owned_write(before: Dictionary, after: Dictionary) -> String:
    # A shared mutable baseline cannot prove an owned write-set: in-place
    # changes would alter both sides and make an illegal write appear equal.
    # Call capture_protected_fields() before mutation for live World checks.
    if is_same(before, after):
        return "market_write_aliased_baseline"
    for location in before:
        if after.has(location) and is_same(before[location], after[location]) and (before[location] is Dictionary):
            return "market_write_aliased_baseline"
    if before.size() != after.size():
        return "market_write_cardinality_changed"
    for location in before:
        if not after.has(location):
            return "market_write_removed_location"
        if not (before[location] is Dictionary) or not (after[location] is Dictionary):
            return "market_write_invalid_row"
        var old_row: Dictionary = before[location]
        var new_row: Dictionary = after[location]
        # Collect protected values once per row rather than rewalking every
        # protected-field x proposed-field pair. The temporary Array only
        # groups references; it never becomes part of the authoritative World.
        var protected_values: Array = []
        for protected_field in old_row:
            if protected_field not in Observation.OBSERVATION_FIELDS:
                protected_values.append(old_row[protected_field])
        if _shares_mutable_storage(protected_values, new_row):
            return "market_write_aliased_protected_field"
        if old_row.size() != new_row.size():
            return "market_write_row_shape_changed"
        for key in old_row:
            if not new_row.has(key):
                return "market_write_removed_field"
            if key in Observation.OBSERVATION_FIELDS:
                continue
            # Structural equality catches nested inventory, credits and
            # physical capacity mutations; never compare by object identity.
            if old_row[key] != new_row[key]:
                return "market_write_outside_observation"
    # A protected container from one market must not be reparented into
    # another location's observation or protected fields. Per-row checks
    # alone miss this cross-location mutable alias.
    # Every same-location alias has already been rejected above. A single
    # global graph comparison catches all remaining cross-location aliases
    # without repeating the nested traversal for each market pair.
    var all_protected_values: Array = []
    for old_location in before:
        var protected_row: Dictionary = before[old_location]
        for protected_field in protected_row:
            if protected_field not in Observation.OBSERVATION_FIELDS:
                all_protected_values.append(protected_row[protected_field])
    if _shares_mutable_storage(all_protected_values, after):
        return "market_write_aliased_protected_field"
    # The existing local proposal validator enforces N150's observation
    # shapes and prices; this guard enforces the complementary write-set.
    return Observation.validate_observation_proposal(
        {"markets": before}, after, -1, 0)

## Detect shared mutable storage at any depth of a protected value.
## Value equality alone cannot prove the baseline is independent.
static func _shares_mutable_storage(old_value: Variant, new_value: Variant) -> bool:
    # Flatten each graph once. The previous recursive cross-search revisited
    # subtrees for every ancestor pair (and could recurse forever on cycles).
    # Identity, not equality, detects protected mutable storage reuse.
    var old_nodes: Array = []
    var new_nodes: Array = []
    _collect_mutable_nodes(old_value, old_nodes)
    _collect_mutable_nodes(new_value, new_nodes)
    for old_node in old_nodes:
        for new_node in new_nodes:
            if is_same(old_node, new_node):
                return true
    return false


static func _collect_mutable_nodes(value: Variant, nodes: Array) -> void:
    # Iterative walk avoids stack overflow on deeply nested market metadata.
    # Seen identities also terminate cycles without dropping shared children.
    var pending: Array = [value]
    while not pending.is_empty():
        var current: Variant = pending.pop_back()
        if not (current is Dictionary or current is Array):
            continue
        var seen: bool = false
        for node in nodes:
            if is_same(node, current):
                seen = true
                break
        if seen:
            continue
        nodes.append(current)
        if current is Dictionary:
            for key in current:
                pending.append(current[key])
        else:
            for item in current:
                pending.append(item)


## Capture only protected market fields before N150 executes. This detached
## boundary detects in-place writes even when before/after World aliases point
## to the same dictionaries. Observation fields remain N150-owned.
static func capture_protected_fields(markets: Dictionary) -> Dictionary:
    var snapshot: Dictionary = {}
    for location in markets:
        if not (markets[location] is Dictionary):
            # Retain malformed locations so validation fails closed.
            snapshot[location] = null
            continue
        var protected: Dictionary = {}
        var row: Dictionary = markets[location]
        for field in row:
            if field not in Observation.OBSERVATION_FIELDS:
                protected[field] = row[field].duplicate(true) if (
                    row[field] is Dictionary or row[field] is Array) else row[field]
        snapshot[location] = protected
    return snapshot


## Use this after a live N150 phase when its before World cannot safely be
## retained as a detached snapshot. No full World or receipts are copied.
## The caller must also run the existing observation proposal validator and
## full Schema oracle; this method only enforces protected ownership.
static func validate_protected_snapshot(snapshot: Dictionary,
        markets: Dictionary) -> String:
    if snapshot.size() != markets.size():
        return "market_write_cardinality_changed"
    for location in snapshot:
        if not markets.has(location):
            return "market_write_removed_location"
        if not (snapshot[location] is Dictionary) or not (markets[location] is Dictionary):
            return "market_write_invalid_row"
        var row: Dictionary = markets[location]
        var protected: Dictionary = snapshot[location]
        var protected_count: int = 0
        for field in row:
            if field in Observation.OBSERVATION_FIELDS:
                continue
            protected_count += 1
            if not protected.has(field):
                return "market_write_added_protected_field"
            if row[field] != protected[field]:
                return "market_write_outside_observation"
        if protected_count != protected.size():
            return "market_write_removed_protected_field"
    return ""

## Combined shadow boundary: validate protected ownership AND the existing N150
## observation rules without retaining an alias to the live World. The synthetic
## baseline contains only detached identity fields; no N9, receipts or ships.
## This is a diagnostic gate, not permission to skip full Schema.validate.
static func validate_shadow_boundary(snapshot: Dictionary,
        markets: Dictionary) -> String:
    var ownership_error: String = validate_protected_snapshot(snapshot, markets)
    if not ownership_error.is_empty():
        return ownership_error
    var baseline: Dictionary = {}
    for location in snapshot:
        var protected: Dictionary = snapshot[location]
        if not protected.has("id"):
            return "market_write_missing_protected_identity"
        baseline[location] = {"id": protected["id"]}
    return Observation.validate_observation_proposal(
        {"markets": baseline}, markets, -1, 0)
