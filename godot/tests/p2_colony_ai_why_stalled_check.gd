extends SceneTree
## Deterministic audit fixture. It demonstrates the mismatch between
## already-agreed AC development and the frozen N92/N111/N154 rules.
## Do NOT enable speculative production or change N39 in this check.
const N151 = preload("res://scripts/sim/phase2/unified_n151_colony_establish.gd")
const N154 = preload("res://scripts/sim/phase1/n154_native_construction_strategy.gd")
const N111 = preload("res://scripts/native_port/n111_options.gd")
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
    # N111 is a shortage-relief comparison, not a T1 development policy.
    # Even a funded, otherwise viable construction cannot become a Head
    # build grant when the target commodity has no reported market demand.
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
    assert(evaluated["selected"] == "wait")
    assert(evaluated["alternatives"][1]["reason"] ==
        "no_projected_shortage_relief")
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
    print("COLONY_AI_WHY_STALLED_DIAGNOSTIC_PASS")
    quit(0)
