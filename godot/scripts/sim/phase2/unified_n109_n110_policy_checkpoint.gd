extends RefCounted
## Frozen Rust Director::{research_mandates,faction_charters} JSON boundary.
## Pure normalized copy for N38 admission AND canonical N39 restore.
## No policy installation, money, world migration or new default charter.
const Research = preload("res://scripts/sim/phase1/n143_native_research_director.gd")
const Charter = preload("res://scripts/native_port/n109_charter.gd")
const Technology = preload("res://scripts/sim/strategy/native_technology_catalog.gd")
const MAX_EXACT_JSON_INT: float = 9007199254740991.0

static func _bad(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}

static func _integer_field(row: Dictionary, field: String) -> bool:
    if not row.has(field):
        return true # Optional Rust serde(default) fields use native defaults.
    var raw: Variant = row[field]
    if typeof(raw) == TYPE_INT:
        return int(raw) >= 0
    if typeof(raw) != TYPE_FLOAT:
        return false
    var value: float = float(raw)
    if not is_finite(value) or value < 0.0 or (
            value > MAX_EXACT_JSON_INT) or floor(value) != value:
        return false
    row[field] = int(value)
    return true

static func normalize(world: Dictionary) -> Dictionary:
    var staged: Dictionary = world.duplicate(true)
    var directors: Variant = staged.get("research_directors", null)
    for kind in ["research_mandates", "faction_charters"]:
        if not staged.has(kind):
            continue # Original Rust old checkpoint: no player controls.
        if not (staged[kind] is Dictionary) or not (
                directors is Dictionary):
            return _bad("n109_n110_json_policy_not_canonical")
        for faction in staged[kind]:
            if not (faction is String) or not directors.has(faction) or (
                    not (staged[kind][faction] is Dictionary)):
                return _bad("n109_n110_json_policy_unknown_faction")
            var entry: Dictionary = staged[kind][faction]
            var fields: Array = []
            if kind == "research_mandates":
                fields = ["budget_ceiling_cr", "treasury_floor_cr",
                    "spent_cr", "created_tick"]
            else:
                fields = ["research_priority", "economy_priority",
                    "shared_ceiling_cr", "protected_treasury_cr",
                    "approved_research_cr", "approved_economy_cr",
                    "spent_cr", "spent_research_cr", "spent_economy_cr",
                    "updated_tick"]
            for field in fields:
                if not _integer_field(entry, field):
                    return _bad("n109_n110_json_policy_not_exact:" +
                        str(faction) + ":" + field)
            var problem: String = ""
            if kind == "research_mandates":
                problem = Research.validate_mandate(entry,
                    Research.catalogue_map(Technology.all()))
            else:
                problem = Charter.validate(entry)
            if not problem.is_empty():
                return _bad("n109_n110_json_policy_invalid:" +
                    str(faction) + ":" + problem)
    return {"ok": true, "world": staged}
