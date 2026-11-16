extends RefCounted
## SystemBalance: opt-in planetocentric orbits for two *verified*
## unmodified Galaxy 0.6.7 Sol bodies. Frozen Rust JSON never changes.
## The derived WorldModel owns the profile; N43 and UI read the same
## authoritatively staged body metadata. Unknown moons are not guessed.
##
## The original Sol orbit_radius=2 represents 1 AU, and its Earth year
## is 700 native time units. We preserve that native calendar and express
## observed sidereal month/year ratios in its units. This is a circular
## 2D approximation, not a real-date ephemeris or a rebalance of travel.
const KM_PER_AU: float = 149597870.7
const SOL_UNITS_PER_AU: float = 2.0
const NATIVE_EARTH_YEAR: float = 700.0
const EARTH_YEAR_DAYS: float = 365.25

## These known identities and legacy source values are *guards*:
## a custom/edited seed is not silently rewritten.
const FROZEN_SOL_SATELLITES: Dictionary = {
    "luna": {
        "parent": "earth", "legacy_radius": 2.1,
        "legacy_period": 735.0, "parent_radius": 2.0,
        "distance_km": 384400.0, "sidereal_days": 27.321661
    },
    "callisto": {
        "parent": "jupiter", "legacy_radius": 10.76,
        "legacy_period": 4350.0, "parent_radius": 10.4,
        "distance_km": 1882700.0, "sidereal_days": 16.689017
    }
}


static func apply_world(world: Dictionary) -> bool:
    if str(world.get("system", {}).get("id", "")) != "system-sol":
        return true
    var incoming: Variant = world.get("bodies", null)
    if not (incoming is Array):
        return false
    var bodies: Dictionary = {}
    for item in incoming:
        if not (item is Dictionary):
            return false
        var body: Dictionary = item
        var bid: String = str(body.get("id", ""))
        if bid.is_empty() or bodies.has(bid):
            return false
        bodies[bid] = body
    for moon_id in FROZEN_SOL_SATELLITES:
        if not bodies.has(moon_id):
            continue
        var moon: Dictionary = bodies[moon_id]
        # Explicit authored physical data always outranks the adapter,
        # including custom seed profiles with different local periods.
        if moon.has("parent_body_id") or moon.has(
                "satellite_orbit_radius_native"):
            continue
        var spec: Dictionary = FROZEN_SOL_SATELLITES[moon_id]
        var parent_id: String = str(spec["parent"])
        if not bodies.has(parent_id):
            continue
        var parent: Dictionary = bodies[parent_id]
        if str(moon.get("type", "")) != "moon" or (
                str(parent.get("type", "")) != "planet"):
            continue
        for pair in [
                [moon.get("orbit_radius", null), spec["legacy_radius"]],
                [moon.get("orbit_period", null), spec["legacy_period"]],
                [parent.get("orbit_radius", null), spec["parent_radius"]]]:
            if not (pair[0] is float or pair[0] is int) or (
                    absf(float(pair[0]) - float(pair[1])) > 0.000001):
                return true # A non-frozen Sol is NOT silently migrated.
        moon["parent_body_id"] = parent_id
        moon["satellite_orbit_radius_native"] = (
            float(spec["distance_km"]) / KM_PER_AU * SOL_UNITS_PER_AU)
        moon["satellite_orbit_period_native"] = (
            NATIVE_EARTH_YEAR * float(spec["sidereal_days"]) /
            EARTH_YEAR_DAYS)
        moon["satellite_profile"] = "sol-parented-circular-v1"
    return true
