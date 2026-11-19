extends RefCounted
## C-owned regression: N140's detached output can be owned by N14 without
## another full-fleet deep copy. No source World, cargo or fuel alias.
const ShipState = preload("res://scripts/sim/ship_state.gd")
const ShipPhase = preload("res://scripts/sim/phase2/unified_ship_phase.gd")
const N140 = preload("res://scripts/sim/phase2/unified_n140_ship_lod_phase.gd")

static func run() -> Dictionary:
    var fleet = ShipState.new()
    if not fleet.add_ship("ship_a", "miner", "faction_a", "system_a"):
        return {"ok": false, "reason": "fixture_ship_catalog"}
    var ship: Dictionary = fleet.ships["ship_a"]
    ship["location"] = "earth"
    ship["cargo"] = {"ore": 3}
    ship["lod"] = {"divisor": 1, "next_tick": 0}
    var world: Dictionary = {
        "ships": fleet.ships.duplicate(true), "ship_next_token": 1}
    var original: Dictionary = world.duplicate(true)
    var positions: Dictionary = {"earth": Vector2.ZERO}
    var opened: Dictionary = ShipPhase._load(world)
    if not opened.get("ok", false):
        return {"ok": false, "reason": "load_" + str(opened.get("reason", ""))}
    var gate: Dictionary = N140.stage(world, positions, 1, 1)
    if not gate.get("ok", false):
        return {"ok": false, "reason": "gate_" + str(gate.get("reason", ""))}
    var old_copy: Dictionary = gate["ships"].duplicate(true)
    var owned: Dictionary = gate["ships"]
    if old_copy != owned:
        return {"ok": false, "reason": "initial_copy_parity"}
    # Mutation of the N14-owned rows must never reach authoritative World,
    # including nested mutable cargo and LOD cursor dictionaries.
    owned["ship_a"]["cargo"]["ore"] = 99
    owned["ship_a"]["lod"]["next_tick"] = 999
    owned["ship_a"]["fuel"] = 0.0
    if world != original:
        return {"ok": false, "reason": "world_mutable_alias"}
    if int(old_copy["ship_a"]["cargo"]["ore"]) != 3:
        return {"ok": false, "reason": "legacy_detach_oracle"}
    # Public output still detaches the fleet before publication to N39.
    var published: Dictionary = {}
    for sid in owned:
        published[str(sid)] = (owned[sid] as Dictionary).duplicate(true)
    published["ship_a"]["cargo"]["ore"] = 7
    if int(owned["ship_a"]["cargo"]["ore"]) != 99:
        return {"ok": false, "reason": "publication_alias"}
    # No transit: normal gate should not invent departure or fuel use.
    var advanced: Dictionary = ShipPhase.advance(world, positions, 1, 1.0, null)
    if not advanced.get("ok", false):
        return {"ok": false, "reason": "advance_" + str(advanced.get("reason", ""))}
    if world != original:
        return {"ok": false, "reason": "advance_mutated_world"}
    if advanced.get("changed", false):
        var row: Dictionary = advanced["ships"]["ship_a"]
        if row.get("cargo") != original["ships"]["ship_a"]["cargo"] or (
                row.get("fuel") != original["ships"]["ship_a"]["fuel"]):
            return {"ok": false, "reason": "cargo_fuel_changed_without_transit"}
        if not (row.get("transit") is Dictionary) or not row["transit"].is_empty():
            return {"ok": false, "reason": "invented_transit"}
    return {"ok": true}
