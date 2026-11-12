extends RefCounted
## N80. Smart idle fallback gates from frozen Rust
## agents/ship/behavior.rs and agents/ship/components.rs.
## Selection of an actual adjacent unexplored system / same-system dock
## comes from WorldRegistry and is NOT fabricated in this pure policy.
const Personality = preload("res://scripts/sim/ships/ai/native_personality.gd")
const IDLE_EXPLORE_TICKS: int = 240
const EXPLORE_MIN_CREDITS: int = 2500
const EXPLORE_MIN_FUEL_FRACTION: float = 0.40
const EXPLORE_CHECK_BOARD_SECONDS: int = 0 # Not used for scoring/dispatch.

## source_neighbors = locations already proven by the Rust-equivalent
## try_build_explore_bt (adjacent, physically traversable, not recently
## explored); source_rest_station = proven same-system dock target or "".
## NO navigation is planned here; this returns only the selected fallback.
static func choose(snapshot: Dictionary, profile: Dictionary) -> Dictionary:
    if not Personality.validate(profile):
        return {"ok": false, "reason": "invalid_personality"}
    var idles: Variant = snapshot.get("idle_ticks", null)
    var credits: Variant = snapshot.get("credits", null)
    var fuel_fraction: Variant = snapshot.get("fuel_fraction", null)
    if not (idles is int) or not (credits is int) or not (fuel_fraction is float or fuel_fraction is int):
        return {"ok": false, "reason": "missing_ship_lifecycle"}
    if int(idles) < 0 or not is_finite(float(fuel_fraction)) or float(fuel_fraction) < 0.0:
        return {"ok": false, "reason": "invalid_ship_lifecycle"}
    var explore_bonus: float = float(profile["exploration"]) - float(profile["safety"]) * 0.5
    var desperation: float = 0.3 if int(credits) < 5000 else 0.0
    var trigger_scale: float = maxf(1.0 - explore_bonus - desperation, 0.25)
    # Rust (f32 as u32) truncates toward zero after clamping.
    var trigger: int = int(float(IDLE_EXPLORE_TICKS) * trigger_scale)
    var permitted: bool = int(idles) >= trigger         and float(fuel_fraction) >= EXPLORE_MIN_FUEL_FRACTION         and int(credits) >= EXPLORE_MIN_CREDITS
    var neighbors: Variant = snapshot.get("reachable_unvisited_neighbors", null)
    if neighbors != null and not (neighbors is Array):
        return {"ok": false, "reason": "invalid_neighbors"}
    if permitted and neighbors is Array and not neighbors.is_empty():
        var destination: String = str(neighbors[0])
        if destination.is_empty():
            return {"ok": false, "reason": "invalid_destination"}
        return {"ok": true, "name": "explore", "destination": destination,
            "trigger_ticks": trigger, "requires_route_planner": true}
    var docked: bool = bool(snapshot.get("docked", false))
    var dockable_here: bool = bool(snapshot.get("dockable_here", false))
    var nearby: String = str(snapshot.get("reachable_same_system_station", ""))
    if not docked and not dockable_here and not nearby.is_empty():
        return {"ok": true, "name": "idle_seek_station", "destination": nearby,
            "trigger_ticks": trigger, "requires_route_planner": true}
    return {"ok": true, "name": "idle", "destination": "",
        "trigger_ticks": trigger, "requires_route_planner": false}
