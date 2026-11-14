extends SceneTree
## Deferred V3 N38 source regression: exact N39 World + N9 + N104 across
## JSON normalization, NO second ledger/World. Not run until final checkpoint.
const Guard = preload("res://scripts/sim/phase2/unified_native_save_roundtrip_guard.gd")
const Saves = preload("res://scripts/sim/save_state.gd")

class FixtureRunner extends RefCounted:
    var source: Dictionary = {}
    func is_started() -> bool:
        return true
    func checkpoint() -> Dictionary:
        return source.duplicate(true)

func _fail(message: String) -> void:
    push_error("P2_N38_ECONOMIC_FRAME: " + message)
    quit(1)

func _expect_rejected(original: Dictionary, modified: Dictionary,
        label: String) -> bool:
    var result: Dictionary = Guard.verify_authoritative_frame(original, modified)
    if result.get("ok", false) or str(result.get("field", "")).is_empty():
        _fail("lossy " + label + " was admitted as safe to promote")
        return false
    return true

func _initialize() -> void:
    var original: Dictionary = {
        "format": "living-sector-godot", "schema_version": 1,
        "scenario": "galaxy-067", "tick": 12,
        "native_production": {
            "version": 1, "tick": 12,
            "world": {
                "markets": {"earth-station": {
                    "id": "market-earth", "supply": {"food": 12.25},
                    "history": {"shortage_ticks": {"food": 200},
                        "crisis_notified": {"food": true}}}},
                "facilities": {"station": {"credits": 1200,
                    "condition": 0.4, "starving_notified": false}},
                "ships": {"ship-1": {"credits": 245,
                    "cargo": {"metals": 200}, "fuel": 7.75}},
                "populations": {"home": {"wealth": 900}},
                "faction_treasuries": {"terran-authority": 240000},
                "escrow_balances": {"escrow:contract:1": 640},
                "contract_board": {"version": 1, "contracts": {
                    "contract:1": {"status": "picked_up", "quantity": 200,
                        "commodity": "metals", "fulfiller_id": "ship-1"}},
                    "receipt_claims": {}},
                "native_execution": {"active": {
                    "terran-authority": {"ledger": {"steps": [
                        {"phase": "planned", "updated_tick": 12}]}}}},
                "cargo_receipts": {"contract:1:load": {
                    "quantity": 200, "tick": 11}},
                "research_receipts": {"research:1": {
                    "tick": 10, "credits": 120}}
            },
            "ledger": {"version": 1,
                "balances": {"faction/terran-authority": 240000,
                    "ship:ship-1": 245, "facility/station": 1200,
                    "population/home": 900,
                    "escrow:contract:1": 640},
                "receipts": {"contract:1:escrow": {
                    "id": "contract:1:escrow", "tick": 10,
                    "kind": "native_contract_escrow",
                    "legs": [
                        {"account": "faction/terran-authority",
                            "delta": -640},
                        {"account": "escrow:contract:1", "delta": 640}
                    ]}}}
        }
    }
    var original_copy: Dictionary = original.duplicate(true)
    var envelope: Dictionary = Saves._wrap(original)
    var encoded: String = JSON.stringify(envelope, "", true, true)
    var parsed: Variant = JSON.parse_string(encoded)
    if not (parsed is Dictionary):
        _fail("N38 roundtrip failed to parse its own envelope")
        return
    var decoded: Dictionary = Saves._unwrap(parsed)
    if decoded.is_empty() or not Saves._physical_stock_matches(original, decoded):
        _fail("N38 SHA envelope or original market stock roundtrip rejected")
        return
    var verified: Dictionary = Guard.verify_authoritative_frame(original, decoded)
    if not verified.get("ok", false):
        _fail("valid N38 native frame rejected: " + str(verified))
        return
    if original != original_copy:
        _fail("N38 normalization changed live source state")
        return

    var changed: Dictionary = decoded.duplicate(true)
    changed["native_production"]["ledger"]["balances"]["ship:ship-1"] = 246
    if not _expect_rejected(original, changed, "N9 ship credits"):
        return
    changed = decoded.duplicate(true)
    changed["native_production"]["ledger"]["receipts"]["contract:1:escrow"]["legs"][0]["delta"] = -639
    if not _expect_rejected(original, changed, "N9 paid escrow receipt"):
        return
    changed = decoded.duplicate(true)
    changed["native_production"]["world"]["contract_board"]["contracts"]["contract:1"]["status"] = "paid"
    if not _expect_rejected(original, changed, "N104 contract status"):
        return
    changed = decoded.duplicate(true)
    changed["native_production"]["world"]["ships"]["ship-1"]["cargo"]["metals"] = 199
    if not _expect_rejected(original, changed, "N15 physical hold"):
        return
    changed = decoded.duplicate(true)
    changed["native_production"]["world"]["markets"]["earth-station"]["history"]["crisis_notified"]["food"] = false
    if not _expect_rejected(original, changed, "native warning flag"):
        return
    changed = decoded.duplicate(true)
    changed["native_production"]["world"]["native_execution"]["active"]["terran-authority"]["ledger"]["steps"][0]["updated_tick"] = 13
    if not _expect_rejected(original, changed, "N121 durable plan step"):
        return
    changed = decoded.duplicate(true)
    changed["native_production"]["world"]["facilities"]["station"].erase("condition")
    if not _expect_rejected(original, changed, "missing facility property"):
        return

    # Godot JSON may represent old i64 credits as floating-point numbers.
    # A nearby 64-bit integer cannot safely round before the SHA is made.
    var too_large: Dictionary = original.duplicate(true)
    too_large["native_production"]["ledger"]["balances"]["ship:ship-1"] = 9007199254740993
    var rounded: Dictionary = too_large.duplicate(true)
    rounded["native_production"]["ledger"]["balances"]["ship:ship-1"] = 9007199254740992.0
    if not _expect_rejected(too_large, rounded, "i64-to-JSON float rounding"):
        return
    # Old P1 snapshots still have no economic frame; do not fabricate one.
    var legacy: Dictionary = {"format": "living-sector-godot", "tick": 12}
    if not Guard.verify_authoritative_frame(legacy, legacy).get("ok", false):
        _fail("legacy P1 no-economic-world checkpoint was rejected")
        return
    if Guard.verify_authoritative_frame(legacy, decoded).get("ok", false):
        _fail("missing real N39 frame silently accepted")
        return
    if original != original_copy:
        _fail("verification mutated authoritative snapshot")
        return

    # Actual SaveState promotion contract: an unsafe .pending may NEVER
    # overwrite the last healthy primary even if its own SHA is valid.
    var runner := FixtureRunner.new()
    runner.source = original.duplicate(true)
    var path: String = "user://tests/p2-native-n38-save-" + str(Time.get_ticks_usec()) + ".json"
    if Saves.save_runner(runner, path) != OK:
        _fail("valid synthetic N39 full economic frame not saved")
        return
    var absolute: String = ProjectSettings.globalize_path(path)
    var on_disk: Dictionary = Saves._read_checkpoint(absolute)
    if not Guard.verify_authoritative_frame(original, on_disk).get("ok", false):
        _fail("healthy primary N38 file did not match source")
        return
    var old_primary: String = FileAccess.get_file_as_string(absolute)
    # JSON can only encode object keys as strings. A numeric dictionary
    # key deep inside the source World would silently change its identity.
    runner.source = original.duplicate(true)
    runner.source["native_production"]["world"]["non_json_index"] = {8: "identity"}
    if Saves.save_runner(runner, path) != ERR_FILE_CORRUPT:
        _fail("lossy native frame was promoted instead of rejected")
        return
    if FileAccess.get_file_as_string(absolute) != old_primary:
        _fail("failed guard damaged last valid primary file")
        return
    if FileAccess.file_exists(absolute + ".bak") or FileAccess.file_exists(absolute + ".pending"):
        _fail("unsafe pending replaced backup or survived failure")
        return
    DirAccess.remove_absolute(absolute)
    print("P2_NATIVE_N38_FULL_ECONOMIC_ROUNDTRIP_GUARD_PASS")
    quit(0)
