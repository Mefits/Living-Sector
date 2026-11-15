extends RefCounted
## N39 II-B shadow guard for N150 observation-only market writes.
## Does not replace Schema.validate or authorize a World/N9 commit.
## The caller supplies detached before/after market dictionaries. No copies
## of the growing receipts, ships, or unrelated World domains are needed.
const Observation = preload("res://scripts/sim/phase1/n39_market_observation_validator.gd")

static func validate_owned_write(before: Dictionary, after: Dictionary) -> String:
    if before.size() != after.size():
        return "market_write_cardinality_changed"
    for location in before:
        if not after.has(location):
            return "market_write_removed_location"
        if not (before[location] is Dictionary) or not (after[location] is Dictionary):
            return "market_write_invalid_row"
        var old_row: Dictionary = before[location]
        var new_row: Dictionary = after[location]
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
    # The existing local proposal validator enforces N150's observation
    # shapes and prices; this guard enforces the complementary write-set.
    return Observation.validate_observation_proposal(
        {"markets": before}, after, -1, 0)
