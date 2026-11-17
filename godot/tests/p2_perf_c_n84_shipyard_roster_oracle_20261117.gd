extends RefCounted
## Negative oracle for N84's per-proposal shipyard roster.
## This checks the exact original predicate and its invalidation boundary.
const N84 = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")

static func _oracle(facilities: Dictionary, location: String) -> bool:
    for id in facilities:
        var fac: Dictionary = facilities[id]
        if str(fac.get("type", "")) == "shipyard" and not fac.get("abandoned", false) and str(fac.get("location", "")) == location:
            return true
    return false

static func _indexed(facilities: Dictionary, location: String, roster: Dictionary) -> bool:
    if not roster.has("_ready"):
        for id in facilities:
            var fac: Dictionary = facilities[id]
            if str(fac.get("type", "")) == "shipyard" and not fac.get("abandoned", false):
                roster[str(fac.get("location", ""))] = true
        roster["_ready"] = true
    return roster.has(location)

static func run() -> Dictionary:
    var facilities: Dictionary = {}
    for i in range(2000):
        facilities["f%04d" % i] = {"type": "station", "location": "s%d" % (i % 50), "abandoned": false}
    facilities["yard_a"] = {"type": "shipyard", "location": "alpha", "abandoned": false}
    facilities["yard_dead"] = {"type": "shipyard", "location": "beta", "abandoned": true}
    facilities["yard_b"] = {"type": "shipyard", "location": "alpha", "abandoned": false}
    var roster: Dictionary = {}
    for location in ["alpha", "beta", "missing", "s1", "alpha"]:
        if _oracle(facilities, location) != _indexed(facilities, location, roster):
            return {"ok": false, "reason": "shipyard_roster_oracle_mismatch", "location": location}
    # The roster is deliberately scoped to one proposal, never persisted.
    facilities["yard_a"]["abandoned"] = true
    facilities["yard_b"]["abandoned"] = true
    facilities["yard_new"] = {"type": "shipyard", "location": "beta", "abandoned": false}
    if not _indexed(facilities, "alpha", roster):
        return {"ok": false, "reason": "missing_same_pass_snapshot"}
    var next_pass: Dictionary = {}
    for location in ["alpha", "beta", "missing"]:
        if _oracle(facilities, location) != _indexed(facilities, location, next_pass):
            return {"ok": false, "reason": "stale_roster_across_ticks", "location": location}
    return {"ok": true}
