extends SceneTree
## Miro Chat #2 B4 regression, NOT RUN until whole Rust->Godot
## integration is ready. Detached fixture only; no real N9/N104 mutation.
const Aftercare = preload("res://scripts/sim/phase2/unified_n92_colony_aftercare.gd")

func _fixture() -> Dictionary:
    return {
        "facilities": {
            "original-colony-dock": {
                "type": "station", "location": "mars-colony",
                "faction": "f1", "crew_count": 0,
                "services": ["market"], "abandoned": false},
            "original-shipyard": {
                "type": "shipyard", "location": "mars-colony",
                "faction": "f1", "crew_count": 3,
                "module_stock": {"stock": {"engine_t2": 1}},
                "abandoned": false}},
        "markets": {"mars-colony": {
            "id": "market-mars-colony", "location": "mars-colony",
            "owner": "original-colony-dock",
            "supply": {"food": 80.0, "water": 2.0,
                "fuel": 10.0, "electronics": 0.0},
            "demand": {"food": 10.0, "water": 6.0}}},
        "populations": {"real-settlers": {
            "location": "mars-colony", "faction": "f1", "count": 50,
            "consumption": {"food": 1.0, "water": 0.6}}},
        "contract_board": {"contracts": {}},
        "faction_treasuries": {"f1": 30000},
        "research_directors": {"f1": {"profile": {"expansion": 1.0}}},
        "native_planner_mode": "htn", "native_planner_records": {},
        "native_execution": {"active": {}}}

func _initialize() -> void:
    var world: Dictionary = _fixture()
    var before: Dictionary = world.duplicate(true)
    var actual: Dictionary = Aftercare.observe(world)
    if not actual.get("ok", false) or actual.get(
            "views", []).size() != 1 or str(actual.get("goals", {}).get(
            "f1", {}).get("commodity", "")) != "water":
        _fail("Rust N92 did not prioritize physical Water shortfall")
        return
    if not bool(actual.get("unsafe_new_colony_factions", {}).get(
            "f1", false)):
        _fail("starving colony did not block speculative new expansion")
        return
    # Frozen source scales per-household purchase rates by resident
    # count / 1000, rather than treating consumption as whole-colony
    # per-purchase amount. 50 residents => minimum reserve 20.
    var actual_view: Dictionary = actual["views"][0]
    if not is_equal_approx(float(actual_view["food_reserve_target"]), 20.0) or (
            not is_equal_approx(float(actual_view["water_reserve_target"]), 20.0)):
        _fail("N92 population-scaled life support reserve diverged")
        return
    var emergency: Dictionary = world.duplicate(true)
    emergency["populations"]["real-settlers"]["count"] = 1000
    emergency["populations"]["real-settlers"]["food_satisfaction"] = 10
    var emergency_view: Dictionary = Aftercare.observe(emergency).get(
        "views", [])[0]
    if not is_equal_approx(float(emergency_view["water_reserve_target"]), 88.0) or (
            not is_equal_approx(float(emergency_view["food_reserve_target"]), 80.0)):
        _fail("N92 frozen emergency water 0.5/1000 below satisfaction 30 missing")
        return
    if actual.get("shipyards", []).size() != 1 or bool(actual.get(
            "hull_autobuild", true)) or world != before:
        _fail("shipyard observation minted a hull/module or changed World")
        return
    var old_head: Dictionary = {
        "selected_option": "build",
        "selected_administrator": "construction",
        "problem": {"goal_id": "expand_production",
            "destination": "earth-station", "commodity": "metals"}}
    var priority: Dictionary = Aftercare.stock_head(world, actual, "f1", old_head)
    if not priority.get("promoted", false) or str(priority.get(
            "head", {}).get("reason", "")) != "colony_life_support_native_goal" or (
            priority.get("fallback_head", {}) != old_head or
            str(priority.get("head", {}).get("selected_option", "")) != "wait"):
        _fail("N92 did not preempt speculative head with real survival goal")
        return
    var paid_water: Dictionary = world.duplicate(true)
    paid_water["contract_board"]["contracts"]["n104-existing-water"] = {
        "status": "picked_up", "contract_type": "delivery",
        "commodity": "water", "quantity": 10,
        "destination_location": "mars-colony",
        "requestor_id": "faction/f1"}
    paid_water["markets"]["mars-colony"]["supply"]["food"] = 10.0
    var independent: Dictionary = Aftercare.observe(paid_water)
    if str(independent.get("goals", {}).get("f1", {}).get(
            "commodity", "")) != "food":
        _fail("in-flight Water incorrectly prevented independent Food plan")
        return
    var fed: Dictionary = world.duplicate(true)
    fed["markets"]["mars-colony"]["supply"]["water"] = 70.0
    fed["markets"]["mars-colony"]["supply"]["food"] = 100.0
    var fueled: Dictionary = Aftercare.observe(fed)
    if str(fueled.get("goals", {}).get("f1", {}).get(
            "commodity", "")) != "fuel":
        _fail("Rust N92 service Fuel priority missing after basic supplies")
        return
    if Aftercare.stock_head(fed, fueled, "f1", old_head).get(
            "promoted", false):
        _fail("non-essential Fuel goal illegally overrode a funded Head build")
        return
    var idle_head: Dictionary = old_head.duplicate(true)
    idle_head["selected_option"] = "wait"
    if not Aftercare.stock_head(fed, fueled, "f1", idle_head).get(
            "promoted", false):
        _fail("N92 waiting director did not consider legitimate Fuel plan")
        return
    var in_flight: Dictionary = world.duplicate(true)
    in_flight["native_planner_records"]["f1"] = {
        "status": "n121_active", "goal": {"destination_id": "mars-colony"}}
    var stayed: Dictionary = Aftercare.stock_head(
        in_flight, Aftercare.observe(in_flight), "f1", old_head)
    if stayed.get("promoted", false):
        _fail("B4 replaced original N98/N121 paid cargo in flight")
        return
    var old_mode: Dictionary = world.duplicate(true)
    old_mode["native_planner_mode"] = "legacy"
    if Aftercare.stock_head(old_mode, actual, "f1", old_head).get(
            "promoted", false):
        _fail("B4 changed default legacy strategy without opt-in")
        return
    var unfunded: Dictionary = world.duplicate(true)
    unfunded["markets"].clear()
    var no_market: Dictionary = Aftercare.observe(unfunded)
    if not no_market.get("ok", false) or not no_market.get(
            "goals", {}).is_empty() or not no_market.get(
            "unsafe_new_colony_factions", {}).has("f1"):
        _fail("empty market spoofed a rescue plan or a safe new colony")
        return
    var fallback: Dictionary = Aftercare.verify_promoted_plan(
        world, "f1", priority, {"ok": true, "due": true,
        "status": "no_source_native_candidate"})
    if not fallback.get("ok", false) or fallback.get("accepted", true):
        _fail("B4 missing-route fallback was not kept observational")
        return
    if world != before:
        _fail("read-only source N92 created cargo, population or money")
        return
    print("P2_CHAT2_B4_RUST_N92_COLONY_AFTERCARE_SOURCE_CHECK_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_CHAT2_B4_SOURCE_FAIL: " + reason)
    quit(1)
