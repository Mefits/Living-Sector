extends SceneTree
## Source-only regression for Rust Bundle(S) readback. NOT RUN until
## final unified Godot checkpoint; no simulated second EventQueue/World.
const Warnings = preload("res://scripts/sim/phase2/unified_native_crisis_events.gd")
const Observer = preload("res://scripts/observer_panel.gd")

func _fail(message: String) -> void:
    push_error("P2_CRISIS_READBACK: " + message)
    quit(1)

func _initialize() -> void:
    var world: Dictionary = {
        "markets": {
            "earth-station": {
                "id": "earth-market",
                "history": {"shortage_ticks": {"food": 204, "water": 50},
                    "crisis_notified": {"food": true, "water": false}}}},
        "facilities": {
            "refinery-a": {"condition": 0.25, "starving_notified": true},
            "refinery-b": {"condition": 0.24},
            "refinery-c": {"condition": 0.45, "starving_notified": true},
            "station-a": {"condition": 0.99}},
        "populations": {},
        "construction_sites": {}
    }
    var before: Dictionary = world.duplicate(true)
    var report: Dictionary = Warnings.current_warning_state(world)
    if not report.get("ok", false) or             report.get("market_count", -1) != 1 or             report.get("facility_count", -1) != 2 or             report.get("pending_facility_count", -1) != 1:
        _fail("invalid persisted-source crisis readback or pending facility staging")
        return
    if report["active_markets"][0].get("commodity", "") != "food" or             report["active_markets"][0].get("shortage_ticks", -1) != 204 or             report["active_facilities"][1].get("facility_id", "") != "refinery-c" or             report["pending_facilities"][0].get("facility_id", "") != "refinery-b":
        _fail("warning rows lost deterministic Rust identities/flags")
        return
    if world != before:
        _fail("Observer read changed the single authoritative World")
        return
    var summary: String = Observer._compact_summary(245, world, {}, {}, {}, report)
    if not summary.contains("Rust сигналы: рынок 1 · объекты 2 · ожидают N39 1"):
        _fail("compact Observer claims unconfirmed events or misses saved flags")
        return
    # A persisted Rust flag remains true between entry <0.3 and
    # recovery >0.5. Condition alone is NOT a new warning event.
    var held: Dictionary = world.duplicate(true)
    held["facilities"]["refinery-c"]["condition"] = 0.5
    var rescan: Dictionary = Warnings.current_warning_state(held)
    if not rescan.get("ok", false) or rescan.get("facility_count", -1) != 2:
        _fail("frozen strict facility hysteresis was changed by readback")
        return
    # Older P2 market snapshots do not have a Rust notification flag yet.
    var legacy: Dictionary = world.duplicate(true)
    legacy["markets"]["earth-station"]["history"].erase("crisis_notified")
    var old_view: Dictionary = Warnings.current_warning_state(legacy)
    if not old_view.get("ok", false) or old_view.get("market_count", -1) != 0:
        _fail("legacy P2 market minted a crisis flag")
        return
    var malformed: Dictionary = world.duplicate(true)
    malformed["markets"]["earth-station"]["history"]["crisis_notified"]["food"] = 1
    if Warnings.current_warning_state(malformed).get("ok", false):
        _fail("integer instead of persisted Rust boolean was accepted")
        return
    print("P2_NATIVE_CRISIS_OBSERVER_PROJECTION_PASS")
    quit(0)
