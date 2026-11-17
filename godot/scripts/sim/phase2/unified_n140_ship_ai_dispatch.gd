extends RefCounted
## Frozen Rust ship/mod.rs::tick_ships: the SAME AgentLod fired map
## gates N84 decisions, not just N14 physical transit. N84 remains the
## original planner/BT executor and one N146 command source. This
## wrapper executes ONLY fired ships on a detached canonical World view.
## No new agent planner, contracts, money or second ship timeline.
const NativeAI = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")

static func propose(world: Dictionary, graph: RefCounted,
        positions: Dictionary, tick: int, tick_scale: float,
        fired: Dictionary, multiplier: int = 1) -> Dictionary:
    if not (world.get("ships") is Dictionary) or tick < 1:
        return {"ok": false, "reason": "n140_n84_no_single_fleet"}
    var ships: Dictionary = world["ships"]
    var active: Dictionary = {}
    for sid in fired:
        if not ships.has(sid) or typeof(fired[sid]) != TYPE_INT or int(fired[sid]) < 1:
            return {"ok": false, "reason": "n140_n84_foreign_fired_ship"}
        # Keep source actor references read-only here: NativeAI.propose
        # deep-copies the isolated active fleet before its first mutation.
        active[str(sid)] = ships[sid]
    if active.is_empty():
        return {"ok": true, "changed": false,
            "ships": ships.duplicate(true),
            "next_token": int(world.get("ship_next_token", 0)),
            "commands": [], "trace": [], "fired": 0,
            "sleeping": ships.size()}
    # NativeAI::propose only iterates World.ships and reads original
    # Market/ContractBoard/site state. A ship that didn't fire may
    # not advance its persistent BT cursor or emit an N146 command.
    # Copy only the outer map. N84 immediately deep-copies this isolated
    # view, so cloning growing markets/history/receipts here was wasted.
    # No reference below is mutated before NativeAI.propose owns its copy.
    var candidate: Dictionary = world.duplicate()
    candidate["ships"] = active
    var result: Dictionary = NativeAI.propose(
        candidate, graph, positions, tick, tick_scale, multiplier)
    if not result.get("ok", false):
        return result
    var proposed: Variant = result.get("ships", null)
    if not (proposed is Dictionary) or proposed.size() != active.size():
        return {"ok": false, "reason": "n140_n84_changed_active_roster"}
    # NativeAI.propose has already detached and mutated every active row.
    # Re-copying its result (and then the entire original fleet) scales
    # with growing cargo/BT history even when only a few ships fired.
    # Detach sleeping rows once; transfer the exclusively owned active
    # rows from the proposal without another recursive copy.
    var merged: Dictionary = {}
    for sid in ships:
        if not active.has(sid):
            merged[sid] = (ships[sid] as Dictionary).duplicate(true)
    for sid in active:
        if not proposed.has(sid) or not (proposed[sid] is Dictionary):
            return {"ok": false, "reason": "n140_n84_lost_active_ship"}
        merged[sid] = proposed[sid]
    for command in result.get("commands", []):
        if not (command is Dictionary) or not fired.has(str(command.get("ship", ""))):
            return {"ok": false, "reason": "n140_n146_command_from_sleeping_ship"}
    result["ships"] = merged
    result["fired"] = active.size()
    result["sleeping"] = ships.size() - active.size()
    return result

