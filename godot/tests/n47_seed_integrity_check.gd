extends SceneTree
const NativeData = preload("res://scripts/native_data.gd")
const Integrity = preload("res://scripts/sim/seed_integrity.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("native seed unavailable: " + str(seed["error"]))
        return
    var before: String = JSON.stringify(seed)
    var baseline: Dictionary = Integrity.inspect(seed)
    if not baseline["ok"]:
        _fail("native baseline rejected: " + str(baseline["errors"]))
        return
    if JSON.stringify(seed) != before or Integrity.inspect(seed) != baseline:
        _fail("read-only/deterministic contract broken")
        return
    var missing: Dictionary = seed.duplicate(true)
    missing["worlds"][0].erase("ships")
    _reject(missing, "missing_ships")
    var duplicate: Dictionary = seed.duplicate(true)
    duplicate["worlds"][1]["system"]["id"] = duplicate["worlds"][0]["system"]["id"]
    _reject(duplicate, "duplicate_id")
    var owner: Dictionary = seed.duplicate(true)
    var found := false
    for world in owner["worlds"]:
        if not world["facilities"].is_empty():
            world["facilities"][0]["faction_id"] = "unknown-n47"
            found = true
            break
    if not found:
        _fail("no native facility fixture")
        return
    _reject(owner, "unknown_faction")
    var invalid: Dictionary = seed.duplicate(true)
    invalid["worlds"][0]["system"]["universe_offset"] = [INF, 0]
    _reject(invalid, "bad_offset")
    if JSON.stringify(seed) != before:
        _fail("fixtures mutated native seed")
        return
    print("N47_SEED_INTEGRITY_PASS: native counts, deterministic audit, four corruptions")
    quit(0)

func _reject(seed: Dictionary, expected: String) -> void:
    var report: Dictionary = Integrity.inspect(seed)
    if report["ok"]:
        _fail("accepted invalid seed: " + expected)
        return
    var matched := false
    for reason in report["errors"]:
        if expected in reason:
            matched = true
    if not matched:
        _fail("missing reason " + expected + ": " + str(report["errors"]))

func _fail(reason: String) -> void:
    push_error("N47_SEED_INTEGRITY_FAIL: " + reason)
    quit(1)
