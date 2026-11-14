extends SceneTree
## Native Rust Bundle(S) market/facility alert parity.
## This regression is staged for the ONE final Godot checkpoint; NOT RUN.
const Warnings = preload("res://scripts/sim/phase2/unified_native_crisis_events.gd")

func _fail(message: String) -> void:
    push_error("P2_NATIVE_CRISIS: " + message)
    quit(1)

func _initialize() -> void:
    var baseline: Dictionary = {"shortage_ticks": {"food": 199},
        "trend_samples": [], "spawned_at_tick": null, "last_tick": 199}
    var before: Dictionary = baseline.duplicate(true)
    var quiet: Dictionary = Warnings.stage_market_history("real-market",
        "earth-station", baseline)
    if not quiet.get("ok", false) or not quiet["events"].is_empty()             or baseline != before:
        _fail("199 ticks generated warning or mutated caller")
        return
    var due: Dictionary = quiet["history"].duplicate(true)
    due["shortage_ticks"]["food"] = 200
    var first: Dictionary = Warnings.stage_market_history("real-market",
        "earth-station", due)
    if not first.get("ok", false) or first["events"].size() != 1             or first["events"][0].get("kind", "") != "market_crisis"             or first["events"][0].get("shortage_ticks", -1) != 200             or first["history"]["crisis_notified"].get("food", false) != true:
        _fail("market crisis crossing was not persisted exactly once")
        return
    var still: Dictionary = first["history"].duplicate(true)
    still["shortage_ticks"]["food"] = 199
    var held: Dictionary = Warnings.stage_market_history("real-market",
        "earth-station", still)
    if not held.get("ok", false) or not held["events"].is_empty()             or held["history"]["crisis_notified"].get("food", false) != true:
        _fail("hysteresis prematurely recovered")
        return
    var recovering: Dictionary = held["history"].duplicate(true)
    recovering["shortage_ticks"]["food"] = 50
    var recovered: Dictionary = Warnings.stage_market_history("real-market",
        "earth-station", recovering)
    if not recovered.get("ok", false) or recovered["events"].size() != 1             or recovered["events"][0].get("kind", "") != "market_recovered"             or recovered["history"]["crisis_notified"].get("food", true) != false:
        _fail("market recovery crossing or persisted flag mismatch")
        return
    var repeat: Dictionary = Warnings.stage_market_history("real-market",
        "earth-station", recovered["history"])
    if not repeat.get("ok", false) or not repeat["events"].is_empty():
        _fail("recovered market emitted duplicate event")
        return
    var broken: Dictionary = baseline.duplicate(true)
    broken["shortage_ticks"]["food"] = -1
    if Warnings.stage_market_history("real-market", "earth-station",
            broken).get("ok", false):
        _fail("invalid native shortage history was accepted")
        return
    var facility: Dictionary = {"refinery-a": {
        "condition": 0.3, "starving_notified": false}}
    var edge: Dictionary = Warnings.propose_facility_warnings(facility)
    if not edge.get("ok", false) or not edge["events"].is_empty():
        _fail("Rust strict threshold at condition 0.3 altered")
        return
    facility["refinery-a"]["condition"] = 0.29
    var starving: Dictionary = Warnings.propose_facility_warnings(facility)
    if not starving.get("ok", false)             or starving["events"].size() != 1             or starving["events"][0].get("kind", "") != "facility_starving"             or starving["flag_updates"].get("refinery-a", false) != true:
        _fail("facility starvation threshold does not match Rust")
        return
    if facility["refinery-a"]["starving_notified"] != false:
        _fail("pure facility proposal mutated authoritative state")
        return
    facility["refinery-a"]["starving_notified"] = true
    facility["refinery-a"]["condition"] = 0.5
    var halfway: Dictionary = Warnings.propose_facility_warnings(facility)
    if not halfway.get("ok", false) or not halfway["events"].is_empty():
        _fail("Rust strict recovery threshold at condition 0.5 altered")
        return
    facility["refinery-a"]["condition"] = 0.51
    var healed: Dictionary = Warnings.propose_facility_warnings(facility)
    if not healed.get("ok", false) or healed["events"].size() != 1             or healed["events"][0].get("kind", "") != "facility_recovered"             or healed["flag_updates"].get("refinery-a", true) != false:
        _fail("facility recovery flag mismatch")
        return
    print("P2_NATIVE_CRISIS_SOURCE_STAGE_PASS")
    quit(0)
