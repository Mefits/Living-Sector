extends SceneTree
## N84 proposal-only envelope vs strict uncached oracle. Run with Godot --headless --script.
const ShipPhase = preload("res://scripts/sim/phase2/unified_ship_phase.gd")

func _initialize() -> void:
    var errors: Array = []
    var ships: Dictionary = {}
    for i in range(500):
        var id: String = "ship_%04d" % i
        ships[id] = {"id": id, "transit": {},
            "cargo": {"ore": i}, "current_bt": {"cursor": [i]},
            "route": ["A", "B"]}
    var world: Dictionary = {"ships": ships, "ship_next_token": 12}
    var scratch: Dictionary = {}
    _same(world, scratch, errors)
    # Read-only cargo/BT/route edits do not affect the envelope, and must
    # never be overwritten by validation or leaked into World/N38.
    var original: Dictionary = world.duplicate(true)
    ships["ship_0001"]["cargo"]["ore"] = 17
    ships["ship_0001"]["current_bt"]["cursor"][0] = 8
    ships["ship_0001"]["route"].append("C")
    _same(world, scratch, errors)
    if ships["ship_0001"]["cargo"]["ore"] != 17 or original["ships"]["ship_0001"]["cargo"]["ore"] == 17:
        errors.append("mutable cargo ownership")
    # All transit/identity edits MUST invalidate the private proposal cache.
    ships["ship_0002"]["transit"] = {"token": 9}
    ShipPhase.invalidate_transit_envelope(scratch)
    _same(world, scratch, errors)
    ships["ship_0003"]["transit"] = {"token": 20}
    ShipPhase.invalidate_transit_envelope(scratch)
    _same(world, scratch, errors)
    if int(scratch.get("max_token", -1)) != 20:
        errors.append("new transit maximum not seen")
    world["ship_next_token"] = 21
    _same(world, scratch, errors)
    ships["ship_0003"]["transit"] = "corrupt"
    ShipPhase.invalidate_transit_envelope(scratch)
    _same(world, scratch, errors)
    ships["ship_0003"]["transit"] = {}
    ships["ship_0004"]["id"] = "wrong"
    ShipPhase.invalidate_transit_envelope(scratch)
    _same(world, scratch, errors)
    ships["ship_0004"]["id"] = "ship_0004"
    ships.erase("ship_0005")
    ShipPhase.invalidate_transit_envelope(scratch)
    _same(world, scratch, errors)
    # Public callers never trust a stale cached maximum, even if token and
    # fleet size have not changed (in-place mutation of another ship).
    ships["ship_0006"]["transit"] = {"token": 200}
    var public_result: Dictionary = ShipPhase.validate_transit_envelope(world, scratch)
    if not public_result.get("ok", false) or int(public_result.get("max_token", -1)) != 200:
        errors.append("public fallback reused stale maximum")
    if errors.is_empty():
        print("PASS p2_perf_c_n84_transit_envelope")
        quit(0)
    else:
        push_error("FAIL p2_perf_c_n84_transit_envelope: " + str(errors))
        quit(1)

func _same(world: Dictionary, scratch: Dictionary, errors: Array) -> void:
    var oracle: Dictionary = ShipPhase.validate_transit_envelope(world)
    var cached: Dictionary = ShipPhase.validate_transit_envelope(world, scratch, true)
    if oracle.get("ok", false) != cached.get("ok", false) or (
            oracle.get("reason", "") != cached.get("reason", "") or
            int(oracle.get("max_token", -1)) != int(cached.get("max_token", -1))):
        errors.append("cached/uncached divergence " + str(oracle) + " vs " + str(cached))
