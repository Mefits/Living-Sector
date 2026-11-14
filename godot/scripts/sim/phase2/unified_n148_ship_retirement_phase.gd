extends RefCounted
## Native N148 adaptive fleet in the ONE N158 ships phase.
## Source: ship/behavior.rs ShipLifecycle + SimCommand::DecommissionShip,
## engine/apply.rs -> drains.rs -> engine/admin.rs. Pure candidate only.
## No second ship tick, wallet, free respawn, physical despawn or fake XP.
const Lifecycle = preload("res://scripts/sim/phase1/n148_native_ship_lifecycle.gd")
const Commands = preload("res://scripts/simulation/native_sim_command_buffer.gd")

static func stage(world: Dictionary, tick: int, multiplier: int,
        n140_fired: Variant = null) -> Dictionary:
    if tick < 1 or multiplier <= 0 or not (world.get("ships") is Dictionary):
        return {"ok": false, "reason": "n148_no_native_ship_clock"}
    if n140_fired != null and not (n140_fired is Dictionary):
        return {"ok": false, "reason": "n148_invalid_native_n140_gate"}
    var ships: Dictionary = world["ships"].duplicate(true)
    if n140_fired is Dictionary:
        for ship_id in n140_fired:
            if not ships.has(ship_id) or typeof(n140_fired[ship_id]) != TYPE_INT or int(n140_fired[ship_id]) < 1:
                return {"ok": false, "reason": "n148_foreign_lod_fire"}
    var ids: Array = ships.keys()
    ids.sort()
    var buffer := Commands.new()
    if not buffer.begin_phase(tick, "ships"):
        return {"ok": false, "reason": "n146_n148_bad_phase"}
    var advanced: Array = []
    for sid in ids:
        # Rust ship/mod.rs::tick_ships passes ONE N140 'active' map
        # through all ship phases; sleeping ships do not accumulate
        # idle ticks or bankruptcy/hoard strikes this tick.
        if n140_fired is Dictionary and not n140_fired.has(str(sid)):
            continue
        var ship: Dictionary = ships[sid]
        var original: Variant = ship.get("lifecycle", null)
        # Old P2 saves predate ShipLifecycle. Reconstruct only Rust's
        # literal NEW component defaults, never persisted strikes/wealth.
        var original_life: Dictionary = (
            original.duplicate(true) if original is Dictionary
            else Lifecycle.default_lifecycle())
        if not Lifecycle._valid_lifecycle(original_life):
            return {"ok": false, "reason": "n148_invalid_saved_lifecycle",
                "ship_id": str(sid)}
        var used: int = 0
        if not (ship.get("cargo") is Dictionary):
            return {"ok": false, "reason": "n148_invalid_actual_cargo"}
        for amount in ship["cargo"].values():
            if typeof(amount) != TYPE_INT or int(amount) < 0:
                return {"ok": false, "reason": "n148_invalid_actual_cargo_amount"}
            used += int(amount)
        var obligation: Variant = ship.get("active_contract_id", null)
        if obligation is String and str(obligation).is_empty():
            obligation = null
        # N140 source fired map is the only actual authority for
        # counting an N148 decision. Old callers with no LOD gate
        # preserve the Rust fallback: every ship fires each tick.
        var facts: Dictionary = {"ship_entity": str(sid),
            "current_goal": str(ship.get("current_goal", "idle")),
            "credits": ship.get("credits", null),
            "cargo_used": used, "active_contract_id": obligation}
        var projected: Dictionary = Lifecycle.lifecycle_step(
            original_life, facts, tick, multiplier, true)
        if not projected.get("ok", false):
            return {"ok": false, "reason": str(projected.get("reason", "n148_step_failed")),
                "ship_id": str(sid)}
        ship["lifecycle"] = projected["lifecycle"].duplicate(true)
        if ship["lifecycle"] != original:
            advanced.append(str(sid))
        for command in projected.get("commands", []):
            if str(command.get("kind", "")) != "decommission_ship" or str(command.get("ship", "")) != str(sid):
                return {"ok": false, "reason": "n148_unrecognized_source_command"}
            var native_command: Dictionary = Commands.make_command("DecommissionShip", {
                "ship": str(sid), "reason": str(command.get("reason", ""))})
            if native_command.is_empty() or not buffer.push(native_command):
                return {"ok": false, "reason": "n146_rejected_real_decommission"}
    return {"ok": true, "changed": not advanced.is_empty(),
        "ships": ships, "advanced": advanced,
        "commands": buffer.drain(), "tick": tick}

