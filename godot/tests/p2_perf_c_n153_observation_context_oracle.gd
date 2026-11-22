extends SceneTree
## N153 read-only proposal-local overlays: compare legacy construction against
## cached variants, including changed quote, origin and independent proposals.
const Dispatch = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")

func _initialize() -> void:
    var failures: Array = []
    var ship: Dictionary = {"price_knowledge": {"Other": {"ore": {"price": 7.0}},
        "Source": {"ore": {"price": 3.0}}}}
    var cache: Dictionary = {}
    var old: Dictionary = ship["price_knowledge"].duplicate()
    old["Source"] = {"ore": {"price": 12.0}}
    var cached: Dictionary = Dispatch._bid_price_observations(cache, "ship-1",
        ship, "Source", "Source", "ore", 12.0)
    _check(cached == old, "source overlay oracle", failures)
    _check(Dispatch._bid_price_observations(cache, "ship-1", ship,
        "Source", "Source", "ore", 12.0) == old, "repeated quote", failures)
    _check(float(ship["price_knowledge"]["Source"]["ore"]["price"]) == 3.0,
        "source World unchanged", failures)
    var changed: Dictionary = Dispatch._bid_price_observations(cache, "ship-1",
        ship, "Source", "Source", "ore", 14.0)
    _check(changed != cached and float(changed["Source"]["ore"]["price"]) == 14.0,
        "changed quote invalidation", failures)
    var other: Dictionary = Dispatch._bid_price_observations(cache, "ship-1",
        ship, "Other", "Source", "ore", 12.0)
    _check(other == ship["price_knowledge"], "non-source original knowledge", failures)
    var new_proposal: Dictionary = Dispatch._bid_price_observations({}, "ship-1",
        {"price_knowledge": {"Source": {"ore": {"price": 20.0}}}},
        "Other", "Source", "ore", 12.0)
    _check(float(new_proposal["Source"]["ore"]["price"]) == 20.0,
        "new proposal sees new World", failures)
    var systems: Dictionary = {"Here": "S1", "Source": "S2", "Dest": "S3"}
    var sys_cache: Dictionary = {}
    var expected: Dictionary = {"Here": "S1", "Source": "S2", "Dest": "S3"}
    var view: Dictionary = Dispatch._bid_system_context(sys_cache, "Here",
        "Source", "Dest", systems)
    _check(view == expected, "system tuple oracle", failures)
    _check(Dispatch._bid_system_context(sys_cache, "Here", "Source", "Dest",
        systems) == expected, "repeated system tuple", failures)
    var missing: Dictionary = Dispatch._bid_system_context(sys_cache, "Here",
        "Source", "Unknown", systems)
    _check(missing["Unknown"] == "", "missing endpoint stays missing", failures)
    var changed_world: Dictionary = {"Here": "S9", "Source": "S2", "Dest": "S3"}
    _check(Dispatch._bid_system_context({}, "Here", "Source", "Dest",
        changed_world)["Here"] == "S9", "next proposal invalidates system", failures)
    _check(Dispatch._bid_system_context({}, "Source", "Source", "Dest",
        systems)["Source"] == "S2", "here equals source", failures)
    if failures.is_empty():
        print("PASS p2_perf_c_n153_observation_context_oracle")
        quit(0)
    else:
        for failure in failures:
            push_error(str(failure))
        quit(1)

func _check(ok: bool, description: String, failures: Array) -> void:
    if not ok:
        failures.append(description)
