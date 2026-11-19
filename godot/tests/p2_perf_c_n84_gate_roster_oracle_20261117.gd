extends RefCounted
## C: original full-facility GateJump scan vs call-scoped N84 roster.
## Exercises actual dispatch, not just a duplicate helper.
const N84 = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

static func _old_gates(facilities: Dictionary, location: String) -> Array:
    var ids: Array = []
    for fid in facilities:
        var fac: Dictionary = facilities[fid]
        if str(fac.get("type", "")) == "gate" and str(
                fac.get("location", "")) == location and fac.get(
                "gate_link", null) is Dictionary:
            ids.append(str(fid))
    return ids

static func run() -> Dictionary:
    var facilities: Dictionary = {}
    for i in range(2000):
        facilities["station_%d" % i] = {"type": "station", "location": "L%d" % (i % 20)}
    facilities["g1"] = {"type": "gate", "location": "A",
        "gate_link": {"paired_gate_id": "g2"}}
    facilities["g2"] = {"type": "gate", "location": "B",
        "gate_link": {"paired_gate_id": "g1"}}
    var ship: Dictionary = {"location": "A", "transit": {},
        "docked_at": "", "credits": 100, "cargo": {"ore": 3},
        "fuel": 50.0}
    var world: Dictionary = {"ships": {"s": ship}, "facilities": facilities}
    var original: Dictionary = world.duplicate(true)
    var scratch: Dictionary = {}
    var action: Dictionary = {"kind": "GateJump", "src_gate": "A", "dest_gate": "B"}
    for i in range(40):
        var result: Dictionary = N84._dispatch(action, {}, world, null, {},
            "s", 10, 1.0, 1, scratch)
        if int(result.get("status", -1)) != Bt.RUNNING or (
                str(result.get("reason", "")) != "n108_wait_exclusive_real_gate_apply"):
            return {"ok": false, "reason": "real_gate_dispatch"}
        if _old_gates(facilities, "A") != scratch["_n84_gate_roster"].get("A", []):
            return {"ok": false, "reason": "legacy_gate_order"}
    if world != original:
        return {"ok": false, "reason": "world_or_cargo_mutated"}
    # A changed facility roster must never reuse another proposal's cache.
    facilities["g3"] = {"type": "gate", "location": "A",
        "gate_link": {"paired_gate_id": "g2"}}
    var fresh: Dictionary = N84._dispatch(action, {}, world, null, {},
        "s", 11, 1.0, 1, {})
    if str(fresh.get("reason", "")) != "n108_unbuilt_or_ambiguous_source_gate":
        return {"ok": false, "reason": "stale_roster_cross_proposal"}
    facilities.erase("g3")
    ship["credits"] = 0
    var unpaid: Dictionary = N84._dispatch(action, {}, world, null, {},
        "s", 12, 1.0, 1, {})
    if str(unpaid.get("reason", "")) != "n108_ship_cannot_pay_source_gate":
        return {"ok": false, "reason": "gate_fee_bypassed"}
    ship["credits"] = 100
    facilities["g2"]["gate_link"]["paired_gate_id"] = "other"
    var broken: Dictionary = N84._dispatch(action, {}, world, null, {},
        "s", 13, 1.0, 1, {})
    if str(broken.get("reason", "")) != "n108_gate_has_no_real_paired_exit":
        return {"ok": false, "reason": "stale_pairing_accepted"}
    return {"ok": true}
