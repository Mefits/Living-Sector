extends SceneTree
## N39 diplomacy writes: shallow World header, detached owned map, full oracle.
## Run: godot --headless --path godot --script res://tests/p2_perf_a_diplomacy_owned_shallow_world_20261116.gd
const NativeData = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

func _initialize() -> void:
    var sim = Runtime.new()
    if not sim.start_from_seed(NativeData.load_current_world()):
        _fail("canonical frozen seed rejected")
        return
    var baseline: Dictionary = sim.production.snapshot()
    var source: Dictionary = baseline["world"]
    if not Schema.validate(source).is_empty():
        _fail("source Schema oracle rejected seed")
        return
    var baseline_accounts: Dictionary = Schema.accounts(source)
    # Exercise both owned N39 diplomacy domains without publishing the
    # shallow staging header or exposing any live authoritative reference.
    for domain in ["body_territory", "faction_relations"]:
        if not source.has(domain):
            continue
        var staged: Dictionary = source.duplicate()
        staged[domain] = source[domain].duplicate(true)
        if staged[domain] is Dictionary:
            staged[domain]["__invalid_owned_write__"] = {"invalid": true}
        # Wrong domain type must be rejected regardless of allowed keys.\n        staged[domain] = 42\n        if Schema.validate(staged).is_empty():
            _fail("full oracle accepted malformed " + domain)
            return
        if source[domain].has("__invalid_owned_write__"):
            _fail("owned diplomacy write aliased source " + domain)
            return
        if Schema.accounts(staged) != baseline_accounts:
            _fail("detached diplomacy write changed canonical accounts")
            return
    if sim.production.snapshot() != baseline:
        _fail("staged negative regression mutated canonical N39/N9")
        return
    # A valid detached no-delta stage must preserve full schema and money.
    var valid: Dictionary = source.duplicate()
    for domain in ["body_territory", "faction_relations"]:
        if source.has(domain):
            valid[domain] = source[domain].duplicate(true)
    if Schema.validate(valid) != "" or Schema.accounts(valid) != baseline_accounts:
        _fail("valid owned stage diverged from full oracle")
        return
    print("P2_PERF_A_DIPLOMACY_OWNED_SHALLOW_WORLD_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_A_DIPLOMACY_OWNED_SHALLOW_WORLD_FAIL: " + reason)
    quit(1)
