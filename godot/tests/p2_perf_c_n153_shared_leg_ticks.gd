extends RefCounted
## N153 per-proposal scalar geometry cache versus original N14 formula.
## No synthetic ship movement or paid cargo transactions are performed.
const Dispatch = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")

static func _legacy_ticks(distance: float, speed: float, scale: float) -> int:
    var velocity: float = Transit.BASE_VELOCITY * speed * scale
    if velocity <= 0.0 or not is_finite(distance) or distance <= 0.0:
        return 0
    return maxi(1, ceili(distance / velocity))

static func _cost(distances: Array, speed: float, rate: float, scale: float,
        cache: Dictionary, optimized: bool) -> Dictionary:
    var cost: float = 0.0
    for distance in distances:
        var ticks: int = Dispatch._physical_leg_ticks(float(distance),
            speed, scale, cache) if optimized else _legacy_ticks(
            float(distance), speed, scale)
        if ticks == 0:
            return {"ok": false, "reason": "invalid_flight_geometry"}
        cost += float(ticks) * rate * scale
    return {"ok": true, "fuel": cost}

static func run() -> Dictionary:
    var cache: Dictionary = {}
    var routes: Array = [
        [10.0, 20.0, 10.0], [20.0, 10.0], [10.0, 20.0],
        [0.001, 2000.0], [3.0, 7.0, 3.0, 7.0]
    ]
    var checked: int = 0
    for speed in [0.5, 1.0, 2.0, 3.25]:
        for rate in [0.05, 0.2, 1.5]:
            for scale in [0.25, 1.0, 2.0]:
                for route in routes:
                    var old: Dictionary = _cost(route, speed, rate, scale, {}, false)
                    var fresh: Dictionary = _cost(route, speed, rate, scale, cache, true)
                    assert(old == fresh, "cached N153 route fuel differs from original")
                    checked += 1
    assert(cache.size() > 0, "no shared leg cache entries were created")
    var before: int = cache.size()
    assert(Dispatch._physical_leg_ticks(10.0, 1.0, 1.0, cache) ==
        _legacy_ticks(10.0, 1.0, 1.0), "repeated leg mismatch")
    assert(cache.size() == before, "repeated leg must not allocate a new key")
    for bad in [0.0, -2.0, INF, NAN]:
        assert(Dispatch._physical_leg_ticks(bad, 1.0, 1.0, cache) == 0,
            "invalid physical leg accepted")
        assert(_cost([10.0, bad, 20.0], 1.0, 0.2, 1.0, cache, true) ==
            _cost([10.0, bad, 20.0], 1.0, 0.2, 1.0, {}, false),
            "negative geometry rejection differs")
    assert(Dispatch._physical_leg_ticks(10.0, 0.0, 1.0, cache) == 0,
        "zero speed must reject")
    assert(Dispatch._physical_leg_ticks(10.0, 1.0, 0.0, cache) == 0,
        "zero tick scale must reject")
    # No cache may escape a proposal: a new N38-restored or changed world
    # creates an empty root, and changed geometry must be recomputed.
    var restored: Dictionary = {}
    var old_count: int = Dispatch._physical_leg_ticks(10.0, 1.0, 1.0, cache)
    var changed_count: int = Dispatch._physical_leg_ticks(100.0, 1.0, 1.0, restored)
    assert(changed_count == _legacy_ticks(100.0, 1.0, 1.0),
        "new proposal retained stale world geometry")
    assert(old_count == _legacy_ticks(10.0, 1.0, 1.0),
        "previous proposal cache was mutated")
    return {"ok": true, "oracle_cases": checked, "negative_cases": 6}
