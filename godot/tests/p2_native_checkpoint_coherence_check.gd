extends SceneTree
## V3 source-only N38/N39/N9 coherence acceptance. NOT RUN until final
## joint integration: this is a small data-only fixture, not synthetic economy.
const Gate = preload("res://scripts/sim/phase2/unified_native_checkpoint_coherence.gd")
const Saves = preload("res://scripts/sim/save_state.gd")

class FixtureRunner extends RefCounted:
    var source: Dictionary = {}
    func is_started() -> bool:
        return true
    func checkpoint() -> Dictionary:
        return source.duplicate(true)

func _fail(reason: String) -> void:
    push_error("P2_N38_COHERENCE: " + reason)
    quit(1)

func _frame() -> Dictionary:
    return {
        "format": "living-sector-godot", "tick": 12,
        "scenario": "galaxy-067", "schema_version": 1,
        "events": {"next_sequence": 2, "pending": [
            {"id": "future", "due_tick": 13, "phase": 10,
                "entity_id": "facility-one", "sequence": 1,
                "kind": "notification", "payload": {}}]},
        "native_production": {
            "version": 1, "tick": 12,
            "world": {
                "facilities": {"one": {"credits": 1200}},
                "populations": {"home": {"wealth": 90}},
                "ships": {"ship-a": {"credits": 245}},
                "faction_treasuries": {"terran-authority": 240000},
                "escrow_balances": {"escrow/order-1": 640},
                "passenger_manifests": {"passenger-one": {"wealth": 30}},
                "markets": {"earth-station": {"supply": {"food": 20.25}}}
            },
            "ledger": {
                "version": 1,
                "balances": {
                    "facility/one": 1200, "population/home": 90,
                    "ship:ship-a": 245, "faction/terran-authority": 240000,
                    "escrow/order-1": 640, "passengers/passenger-one": 30},
                "receipts": {
                    "contract:one:post": {"id": "contract:one:post",
                        "kind": "contract_advance", "tick": 10,
                        "legs": [
                            {"account": "faction/terran-authority", "delta": -640},
                            {"account": "escrow/order-1", "delta": 640}]},
                    # Native ship crew wages have a legitimate single-leg
                    # sink; do not falsely require zero-sum receipt history.
                    "crew:ship-a": {"id": "crew:ship-a",
                        "kind": "native_ship_crew_wages", "tick": 11,
                        "legs": [
                            {"account": "ship:ship-a", "delta": -10}]}
                }
            }
        }
    }

func _reject(base: Dictionary, path: Array, bad_value: Variant,
        expected_reason: String) -> bool:
    var data: Dictionary = base.duplicate(true)
    var current: Dictionary = data
    for index in range(path.size() - 1):
        current = current[path[index]]
    current[path[-1]] = bad_value
    var answer: Dictionary = Gate.validate(data)
    if answer.get("ok", false) or not str(answer.get("reason", "")).begins_with(expected_reason):
        _fail("invalid checkpoint accepted for %s: %s" % [str(path), str(answer)])
        return false
    return true

func _initialize() -> void:
    var clean: Dictionary = _frame()
    var before: Dictionary = clean.duplicate(true)
    var valid: Dictionary = Gate.validate(clean)
    if not valid.get("ok", false) or valid.get("accounts_checked", -1) != 6             or valid.get("receipts_checked", -1) != 2:
        _fail("actual source account prefixes, N149 sink, N38 queue not accepted: " + str(valid))
        return
    if not _reject(clean, ["native_production", "world",
            "faction_treasuries", "terran-authority"], 240001,
            "n9_world_account_diverged"):
        return
    if not _reject(clean, ["native_production", "ledger",
            "balances", "facility/one"], 1201, "n9_world_account_diverged"):
        return
    if not _reject(clean, ["native_production", "ledger",
            "receipts", "contract:one:post", "tick"], 13,
            "n9_receipt_from_future"):
        return
    if not _reject(clean, ["native_production", "ledger",
            "receipts", "contract:one:post", "id"], "forged-receipt",
            "n9_receipt_id_mismatch"):
        return
    if not _reject(clean, ["events", "pending"], [
            {"id": "past-due", "due_tick": 12, "phase": 10,
                "entity_id": "facility-one", "kind": "notification"}],
            "stale_or_invalid_native_event"):
        return
    if not _reject(clean, ["native_production", "tick"], 11,
            "native_world_tick_mismatch"):
        return
    var forged: Dictionary = clean.duplicate(true)
    forged["native_production"]["ledger"]["balances"]["ghost/coin"] = 9
    if Gate.validate(forged).get("ok", false):
        _fail("extra wallet unknown to canonical N39 World accepted")
        return
    forged = clean.duplicate(true)
    forged["native_production"]["world"]["escrow_balances"]["facility/one"] = 5
    if Gate.validate(forged).get("ok", false):
        _fail("escrow key collided with real facility wallet")
        return
    if clean != before:
        _fail("pure N38 audit mutated an original World")
        return

    # This is a real SaveState promotion test without running the simulation.
    var runner := FixtureRunner.new()
    runner.source = clean.duplicate(true)
    var path: String = "user://tests/p2-v3-coherence-" + str(Time.get_ticks_usec()) + ".json"
    if Saves.save_runner(runner, path) != OK:
        _fail("healthy coherent native N38 save rejected")
        return
    var absolute: String = ProjectSettings.globalize_path(path)
    var bytes_before: String = FileAccess.get_file_as_string(absolute)
    if bytes_before.is_empty():
        _fail("healthy N38 primary not created")
        return
    runner.source["native_production"]["ledger"]["balances"]["ghost/coin"] = 9
    if Saves.save_runner(runner, path) != ERR_INVALID_DATA:
        _fail("extra N9 wallet was not rejected before writing pending file")
        return
    if FileAccess.get_file_as_string(absolute) != bytes_before or             FileAccess.file_exists(absolute + ".bak") or             FileAccess.file_exists(absolute + ".pending"):
        _fail("rejected incoherent save altered healthy primary or backup")
        return
    DirAccess.remove_absolute(absolute)
    var legacy: Dictionary = {"tick": 12}
    if not Gate.validate(legacy).get("ok", false):
        _fail("P1 legacy source without N39 was not permitted")
        return
    print("P2_V3_CANONICAL_N38_N39_N9_COHERENCE_PASS")
    quit(0)
