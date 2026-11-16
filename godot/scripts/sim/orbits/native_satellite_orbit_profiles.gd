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
## Only the verified frozen Sol presentation has known physical radii.
## Other systems retain original Rust facility radius until they provide
## explicit physical body metadata; never guess physical sizes by biome.
const SOL_BODY_RADII_KM: Dictionary = {
    "mercury": 2439.7, "venus": 6051.8, "earth": 6371.0,
    "luna": 1737.4, "mars": 3389.5, "jupiter": 69911.0,
    "saturn": 58232.0, "callisto": 2410.3
}
## A provisional near-body docking altitude, not a new economy formula.
## The fixed native N43 0.55 radius put stations 100+ lunar radii away.
const STATION_ALTITUDE_KM: float = 400.0
const NAVIGATION_GEOMETRY_VERSION: String = "sol-stations-local-v1"

static func physical_radius_native(body_id: String) -> float:
    if not SOL_BODY_RADII_KM.has(body_id):
        return 0.0
    return float(SOL_BODY_RADII_KM[body_id]) / KM_PER_AU * SOL_UNITS_PER_AU


static func compact_station_orbit_radius(body_id: String) -> float:
    var radius: float = physical_radius_native(body_id)
    if radius <= 0.0:
        return 0.0
    return radius + STATION_ALTITUDE_KM / KM_PER_AU * SOL_UNITS_PER_AU

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
    # Validate the entire matching legacy group before committing any
    # patch. A partially edited Sol must not become half-migrated.
    var candidates: Array = []
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
        candidates.append(moon_id)
    # Navigation geometry is versioned inside the canonical World
    # fingerprint. Old transits cannot quietly resume with a different
    # physical origin/destination after a checkpoint reload.
    if candidates.size() == FROZEN_SOL_SATELLITES.size():
        world["navigation_geometry_profile"] = NAVIGATION_GEOMETRY_VERSION
    for moon_id in candidates:
        var moon: Dictionary = bodies[moon_id]
        var spec: Dictionary = FROZEN_SOL_SATELLITES[moon_id]
        moon["parent_body_id"] = str(spec["parent"])
        moon["satellite_orbit_radius_native"] = (
            float(spec["distance_km"]) / KM_PER_AU * SOL_UNITS_PER_AU)
        moon["satellite_orbit_period_native"] = (
            NATIVE_EARTH_YEAR * float(spec["sidereal_days"]) /
            EARTH_YEAR_DAYS)
        moon["satellite_profile"] = "sol-parented-circular-v1"
    return true
