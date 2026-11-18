extends SceneTree
## Deterministic colony regression: genuine N154 infrastructure may
## bypass shortage-profit evaluation, but never physical source, funding,
## forecast provenance or N39 mutations.
const N151 = preload("res://scripts/sim/phase2/unified_n151_colony_establish.gd")
const N154 = preload("res://scripts/sim/phase1/n154_native_construction_strategy.gd")
const N111 = preload("res://scripts/native_port/n111_options.gd")
const N134Head = preload("res://scripts/sim/phase1/n134_coordination_head.gd")
const N92 = preload("res://scripts/ported/n92_colony_development.gd")
const Trace = preload("res://scripts/view/strategy_decision_projection.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    # Original Sol seed: Venus is molten, ice=0.2 and gas=0.8.
    var new_market: Dictionary = N151.native_market(
        "venus-colony", "station-venus", 1)
    assert(not new_market.is_empty())
    assert(new_market["supply"].is_empty())
    assert(new_market["demand"] == {"food": 5.0, "water": 3.0})
    var next: String = N154._next_colony_commodity(
        [{"id": "station-venus", "faction_id": "faction-1",
            "location_name": "venus-colony", "facility_type": "station"}],
        "faction-1", "venus-colony", {"ice": 0.2, "gas": 0.8})
    assert(next == "ice")
    # Market demand for ice is zero. Real N154-ready infrastructure should
    # no longer fail solely because it cannot show immediate shortage relief.
    var forecast: Dictionary = {
        "reason": "ready", "remaining": 600, "shipments": 3,
        "material": "metals", "total_cost": 50150,
        "source": "earth-station", "source_stock": 600,
        "first_purchase_cost": 9000, "native_output_units": 100,
        "native_input_cost": 0
    }
    var evaluated: Dictionary = N111.compare_goal({
        "goal_id": "develop_colony", "commodity": "ice",
        "destination": "venus-colony", "score": 100
    }, new_market, {}, forecast, 100000, 1,
        100, 120, 1600, 10000, 200)
    assert(evaluated["selected"] == "build")
    assert(evaluated["alternatives"][1]["status"] == "ready")
    assert(evaluated["alternatives"][1]["reason"] ==
        "strategic_colony_infrastructure")
    assert(evaluated["alternatives"][1]["estimated_net_value"] == null)
    var head: Dictionary = N134Head.preview(
        {"treasury": 100000}, evaluated, 600, 1, false)
    assert(head["selected_option"] == "build")
    assert(head["reason"] == "strategic_colony_infrastructure")
    # Must not turn normal shortage projects into free strategic subsidies.
    var normal: Dictionary = N111.compare_goal({
        "goal_id": "expand_production", "commodity": "ice",
        "destination": "venus-colony", "score": 100
    }, new_market, {}, forecast, 100000, 1,
        100, 120, 1600, 10000, 200)
    assert(normal["selected"] == "wait")
    var not_colony: Dictionary = N111.compare_goal({
        "goal_id": "develop_colony", "commodity": "ice",
        "destination": "venus-station", "score": 100
    }, new_market, {}, forecast, 100000, 1,
        100, 120, 1600, 10000, 200)
    assert(not_colony["selected"] == "wait")
    # No valid external source, money, approved offer or native forecast
    # means NO authority. All four must leave the action at 'wait'.
    var empty_source: Dictionary = forecast.duplicate(true)
    empty_source["source"] = ""
    var empty_result: Dictionary = N111.compare_goal({
        "goal_id": "develop_colony", "commodity": "ice",
        "destination": "venus-colony"
    }, new_market, {}, empty_source, 100000, 1,
        100, 120, 1600, 10000, 200)
    assert(empty_result["selected"] == "wait")
    var too_expensive: Dictionary = forecast.duplicate(true)
    too_expensive["total_cost"] = 120000
    var budget_result: Dictionary = N111.compare_goal({
        "goal_id": "develop_colony", "commodity": "ice",
        "destination": "venus-colony"
    }, new_market, {}, too_expensive, 100000, 1,
        100, 120, 1600, 10000, 200)
    assert(budget_result["selected"] == "wait")
    var missing_forecast: Dictionary = forecast.duplicate(true)
    missing_forecast.erase("native_output_units")
    var provenance_result: Dictionary = N111.compare_goal({
        "goal_id": "develop_colony", "commodity": "ice",
        "destination": "venus-colony"
    }, new_market, {}, missing_forecast, 100000, 1,
        100, 120, 1600, 10000, 200)
    assert(provenance_result["selected"] == "wait")
    var blocked: Dictionary = forecast.duplicate(true)
    blocked["reason"] = "no_accessible_stock"
    var blocked_result: Dictionary = N111.compare_goal({
        "goal_id": "develop_colony", "commodity": "ice",
        "destination": "venus-colony"
    }, new_market, {}, blocked, 100000, 1,
        100, 120, 1600, 10000, 200)
    assert(blocked_result["selected"] == "wait")
    # N92 instead prioritizes life-support when an actual household has
    # an unambiguous empty market. This can preempt development at N134.
    var observations: Array = N92.observe([{
        "faction_id": "faction-1", "location": "venus-colony",
        "station_type": "station", "population": 10,
        "facilities": [{"type": "station", "crew_count": 0}],
        "market_count": 1, "market_owned_by_station": true,
        "stock": {}, "demand": new_market["demand"],
        "food_per_purchase": 1.0, "water_per_purchase": 1.0,
        "required_workers": 0, "pending_passenger_contract": ""
    }])
    assert(observations.size() == 1)
    assert(observations[0]["phase"] == "life_support")
    assert(observations[0]["reason"] ==
        "colony_essential_reserve_below_target")
    var trace: Dictionary = Trace.build({
        "strategy_trace": {"tick": 600,
            "factions": {"faction-1": {
                "head": {"selected_option": "wait",
                    "reason": "source_n134_wait"},
                "construction": {
                    "status": "blocked",
                    "reason": "no_accessible_stock",
                    "selected_goal": {
                        "goal_id": "develop_colony",
                        "destination": "venus-colony",
                        "commodity": "ice"},
                    "offers": [{
                        "goal": {"goal_id": "develop_colony",
                            "commodity": "ice",
                            "destination": "venus-colony"},
                        "facility_type": "mining_rig",
                        "reason": "no_accessible_stock",
                        "ready": false,
                        "delivery_commodity": "metals",
                        "total_cost": 50150
                    }]
                }
            }}
        }
    }, {"facilities": {"station-venus": {
        "body_id": "venus", "type": "station", "faction": "faction-1",
        "location": "venus-colony"
    }}}, "venus")
    assert(trace["factions"].size() == 1)
    assert(trace["factions"][0]["offers"][0]["building"] == "mining_rig")
    assert(Trace.reason_text("no_accessible_stock") !=
        "no_accessible_stock")
    print("COLONY_AI_INFRASTRUCTURE_ADMISSION_GUARDS_PASS")
    quit(0)
