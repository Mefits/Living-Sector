extends RefCounted
## N140/N84 merge: active rows are already detached by NativeAI.propose.
## Independent legacy deep-copy oracle, nested paid cargo/BT and sleeping
## ship isolation. Exercises the real dispatcher with an idle active ship.
const ShipState = preload("res://scripts/sim/ship_state.gd")
const N140AI = preload("res://scripts/sim/phase2/unified_n140_ship_ai_dispatch.gd")

static func run() -> Dictionary:
    var fleet = ShipState.new()
    if not fleet.add_ship("active", "miner", "faction_a", "system_a"):
        return {"ok": false, "reason": "active_fixture"}
    if not fleet.add_ship("sleeping", "miner", "faction_b", "system_b"):
        return {"ok": false, "reason": "sleeping_fixture"}
    var ships: Dictionary = fleet.ships.duplicate(true)
    ships["active"]["cargo"] = {"ore": 4}
    ships["sleeping"]["cargo"] = {"ice": 9}
    ships["sleeping"]["active_contract_id"] = "paid-17"
    ships["sleeping"]["current_bt"] = {"kind": "Sequence", "children": []}
    var world: Dictionary = {"ships": ships, "ship_next_token": 1}
    var before: Dictionary = world.duplicate(true)
    var result: Dictionary = N140AI.propose(
        world, RefCounted.new(), {}, 1, 1.0, {"active": 1})
    if not result.get("ok", false):
        return {"ok": false, "reason": "real_dispatch_" + str(result.get("reason", ""))}
    if world != before:
        return {"ok": false, "reason": "source_mutated"}
    if result["ships"] != before["ships"]:
        return {"ok": false, "reason": "legacy_value_oracle"}
    # A legacy full deep copy of the source fleet must have identical
    # sleeping data; active rows must be independent of the source too.
    var legacy: Dictionary = before["ships"].duplicate(true)
    for sid in ["active", "sleeping"]:
        if result["ships"][sid] != legacy[sid]:
            return {"ok": false, "reason": "ship_value_parity_" + sid}
    result["ships"]["active"]["cargo"]["ore"] = 99
    result["ships"]["sleeping"]["cargo"]["ice"] = 77
    result["ships"]["sleeping"]["current_bt"]["children"].append({"paid": true})
    if world != before or int(legacy["active"]["cargo"]["ore"]) != 4:
        return {"ok": false, "reason": "mutable_alias"}
    if int(legacy["sleeping"]["cargo"]["ice"]) != 9 or (
            legacy["sleeping"]["current_bt"]["children"].size() != 0):
        return {"ok": false, "reason": "paid_sleeping_alias"}
    if result.get("commands", []).size() != 0:
        return {"ok": false, "reason": "invented_paid_command"}
    return {"ok": true}
