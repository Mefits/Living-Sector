extends RefCounted
## N80. Exact immutable defaults from frozen Rust ai/personality.rs.
## Seeded ships use persisted random_ship() personality, NOT class fallback.
## RNG selection belongs to Rust source replay / later spawn adapter; this
## module never silently chooses a random archetype or generates new data.

const AXES = ["profit", "safety", "morale", "exploration", "loyalty", "aggression"]
const SHIP_RANDOM_ARCHETYPES = [
    "cautious_trader", "aggressive_trader", "balanced_trader", "explorer",
    "reliable_trucker", "opportunistic_trucker", "courier"
]
const CREW_RANDOM_ARCHETYPES = ["diligent", "self_preserving", "balanced_trader"]
const PROFILES = {
    "cautious_trader": {
        "profit": 0.6, "safety": 0.9, "morale": 0.5, "exploration": 0.1,
        "loyalty": 0.7, "aggression": 0.0,
        "prefer_goals": {"fulfill_contract": 0.3, "fulfill_delivery": 0.3,
            "station_job": 0.2}
    },
    "aggressive_trader": {
        "profit": 0.95, "safety": 0.2, "morale": 0.2, "exploration": 0.3,
        "loyalty": 0.3, "aggression": 0.1,
        "prefer_goals": {"trade_run": 0.3}
    },
    "balanced_trader": {
        "profit": 0.7, "safety": 0.5, "morale": 0.4, "exploration": 0.3,
        "loyalty": 0.5, "aggression": 0.0, "prefer_goals": {}
    },
    "explorer": {
        "profit": 0.3, "safety": 0.5, "morale": 0.4, "exploration": 0.9,
        "loyalty": 0.2, "aggression": 0.0,
        "prefer_goals": {"explore": 0.4}
    },
    "reliable_trucker": {
        "profit": 0.5, "safety": 0.7, "morale": 0.5, "exploration": 0.1,
        "loyalty": 0.9, "aggression": 0.0,
        "prefer_goals": {"fulfill_delivery": 0.4, "fulfill_contract": 0.3}
    },
    "opportunistic_trucker": {
        "profit": 0.7, "safety": 0.4, "morale": 0.3, "exploration": 0.2,
        "loyalty": 0.7, "aggression": 0.1,
        "prefer_goals": {"fulfill_delivery": 0.25, "trade_run": 0.2}
    },
    "courier": {
        "profit": 0.6, "safety": 0.8, "morale": 0.7, "exploration": 0.2,
        "loyalty": 0.8, "aggression": 0.0,
        "prefer_goals": {"fulfill_passenger_transport": 0.35,
            "fulfill_courier": 0.30, "fulfill_delivery": 0.25,
            "station_job": 0.15}
    },
    "miner": {
        "profit": 0.5, "safety": 0.6, "morale": 0.4, "exploration": 0.3,
        "loyalty": 0.6, "aggression": 0.0,
        "prefer_goals": {"mine": 0.4, "fulfill_delivery": 0.2,
            "station_job": 0.15}
    },
    "diligent": {
        "profit": 0.3, "safety": 0.4, "morale": 0.3, "exploration": 0.1,
        "loyalty": 0.9, "aggression": 0.0, "prefer_goals": {}
    },
    "self_preserving": {
        "profit": 0.5, "safety": 0.9, "morale": 0.8, "exploration": 0.2,
        "loyalty": 0.2, "aggression": 0.1, "prefer_goals": {}
    }
}

static func archetype(name: String) -> Dictionary:
    if not PROFILES.has(name):
        return {}
    return (PROFILES[name] as Dictionary).duplicate(true)

## The Rust seeder's fallback and admin_spawn_ship defaults, NOT a
## reconstruction of the random personality given to existing seeded ships.
static func for_class(ship_class: String) -> Dictionary:
    match ship_class:
        "courier", "colonizer":
            return archetype("courier")
        "freighter", "tanker":
            return archetype("reliable_trucker")
        "hauler":
            return archetype("opportunistic_trucker")
        "miner":
            return archetype("miner")
        _:
            return archetype("balanced_trader")

static func validate(profile: Dictionary) -> bool:
    if not (profile.get("prefer_goals", null) is Dictionary):
        return false
    for key in AXES:
        var value: Variant = profile.get(key, null)
        if not (value is int or value is float):
            return false
        if not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0:
            return false
    var goals: Dictionary = profile["prefer_goals"]
    for key in goals:
        if not (key is String) or (key as String).is_empty():
            return false
        var bonus: Variant = goals[key]
        if not (bonus is int or bonus is float) or not is_finite(float(bonus)):
            return false
    return true

## Rust Personality::drift(axis, delta): mutate only one axis and clamp.
## Pure version for data-only command planning; caller persists its result.
static func drift(profile: Dictionary, axis: String, delta: float) -> Dictionary:
    if not validate(profile) or not AXES.has(axis) or not is_finite(delta):
        return {}
    var result: Dictionary = profile.duplicate(true)
    result[axis] = clampf(float(result[axis]) + delta, 0.0, 1.0)
    return result

## The Rust with_variation() first draws seven? No: exactly SIX
## independent inclusive ±0.1 draws and rounds each axis to 2 places.
## Pass the six source RNG draws rather than substituting a Godot RNG.
## This keeps the interface ready for precise Rust-seed RNG replay.
static func with_source_variation(profile: Dictionary, deltas: Dictionary) -> Dictionary:
    if not validate(profile) or deltas.size() != AXES.size():
        return {}
    var result: Dictionary = profile.duplicate(true)
    for axis in AXES:
        if not deltas.has(axis):
            return {}
        var value: Variant = deltas[axis]
        if not (value is int or value is float) or not is_finite(float(value)):
            return {}
        if float(value) < -0.1 or float(value) > 0.1:
            return {}
        result[axis] = roundf(clampf(float(result[axis]) + float(value),
            0.0, 1.0) * 100.0) / 100.0
    return result

## Rust random_ship() chooses uniformly from the seven ship archetypes,
## then with_variation(). The caller supplies the original sampled index.
static func from_ship_rng_draw(index: int, deltas: Dictionary) -> Dictionary:
    if index < 0 or index >= SHIP_RANDOM_ARCHETYPES.size():
        return {}
    return with_source_variation(archetype(SHIP_RANDOM_ARCHETYPES[index]), deltas)

static func from_crew_rng_draw(index: int, deltas: Dictionary) -> Dictionary:
    if index < 0 or index >= CREW_RANDOM_ARCHETYPES.size():
        return {}
    return with_source_variation(archetype(CREW_RANDOM_ARCHETYPES[index]), deltas)
