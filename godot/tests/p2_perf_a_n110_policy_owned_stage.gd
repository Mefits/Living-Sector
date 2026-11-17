extends SceneTree
# N109/N110 policy write-set isolation against a full deep-copy oracle.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n110_policy_owned_stage.gd

const POLICY_KEYS: Array[String] = ["research_mandates", "faction_charters",
    "economic_mandates"]

func _owned_stage(source: Dictionary) -> Dictionary:
    var stage: Dictionary = source.duplicate(false)
    for key in POLICY_KEYS:
        if source.has(key) and source[key] is Dictionary:
            stage[key] = source[key].duplicate(true)
    for key in POLICY_KEYS:
        if stage.has(key) and not (stage[key] is Dictionary):
            return {}
        if not stage.has(key):
            stage[key] = {}
    return stage

func _initialize() -> void:
    var source: Dictionary = {
        "research_mandates": {"f": {"nested": {"priority": 1}}},
        "faction_charters": {"f": {"rules": ["a"]}},
        "economic_mandates": {"f": {"spent_cr": 7}},
        "ships": {"s": {"cargo": {"ore": 3}}},
        "markets": {"m": {"supply": {"ice": 4}}},
        "research_directors": {"f": {"technologies": ["t0"]}}}
    var frozen: Dictionary = source.duplicate(true)
    var oracle: Dictionary = source.duplicate(true)
    var stage: Dictionary = _owned_stage(source)
    for candidate in [oracle, stage]:
        candidate["research_mandates"]["f"]["nested"]["priority"] = 2
        candidate["faction_charters"]["f"]["rules"].append("b")
        candidate["economic_mandates"]["f"]["spent_cr"] = 9
    assert(stage == oracle, "policy write stage differs from full-copy oracle")
    assert(source == frozen, "rejected policy stage modified authoritative World")
    stage["research_mandates"]["f"]["nested"]["priority"] = -5
    assert(source == frozen, "nested policy mutation leaked into World")
    var legacy: Dictionary = {"ships": {"s": {"cargo": {"ore": 3}}}}
    var legacy_stage: Dictionary = _owned_stage(legacy)
    assert(legacy_stage.has("research_mandates"))
    assert(legacy_stage.has("faction_charters"))
    assert(legacy_stage.has("economic_mandates"))
    assert(not legacy.has("research_mandates"), "legacy source gained a map")
    var invalid: Dictionary = {"research_mandates": ["bad"]}
    assert(_owned_stage(invalid).is_empty(),
        "malformed policy map must be rejected")
    # Negative fixture: shallow nested policy alias would corrupt authority.
    var unsafe: Dictionary = frozen.duplicate(false)
    unsafe["research_mandates"] = frozen["research_mandates"].duplicate(false)
    unsafe["research_mandates"]["f"]["nested"]["priority"] = -100
    assert(frozen["research_mandates"]["f"]["nested"]["priority"] == -100,
        "negative fixture did not reproduce alias corruption")
    quit(0)
