extends RefCounted
## N80. Frozen Rust agents/ship/behavior.rs: score/choose phase of
## plan_goal, without running a BT, mutating the ECS, or inventing
## profitability. Inputs from contract/market/route/retrofit selectors
## MUST be externally AUTHORITATIVE and feasible. This returns GOAL INTENTS.
const Personality = preload("res://scripts/sim/ships/ai/native_personality.gd")

const TIER_BIO_WEIGHT: float = 100.0
const TIER_HOUSEKEEPING_WEIGHT: float = 40.0
const TIER_STRATEGIC_WEIGHT: float = 3.0
const TIER_EXPLORE_WEIGHT: float = 6.0
const TIER_IDLE_FLOOR: float = 0.5
const FUEL_URGENCY_ONSET: float = 0.45
const CREW_REST_TRIGGER: float = 15.0
const REPLAN_MIN_COMMIT_TICKS: int = 40
const REPLAN_CHECK_INTERVAL_TICKS: int = 40
const REPLAN_SCORE_RATIO: float = 1.30
const CONTRACT_OBLIGATION_WEIGHT: float = 0.5
const LOYALTY_REPLAN_MULTIPLIER: float = 0.5

const NON_INTERRUPTABLE = [
    "rest_crew", "refuel", "seek_retrofit", "sell_cargo",
    "fulfill_delivery_with_retrofit", "trade_run_with_retrofit",
    "mine_ice", "deliver_mined_ice"
]

static func is_replan_eligible(goal: String) -> bool:
    return not NON_INTERRUPTABLE.has(goal)

## Rust fn score_strategic: log-profit (integer credits), archetype
## preference and contested bonus only if aggression > 0.5.
static func score_strategic(profit: int, goal_name: String,
        profile: Dictionary, contested_zone: bool) -> float:
    if not Personality.validate(profile) or profit <= 0:
        return 0.0
    var bonus: float = float((profile["prefer_goals"] as Dictionary).get(goal_name, 0.0))
    var contested: float = float(profile["aggression"]) * 0.4         if contested_zone and float(profile["aggression"]) > 0.5 else 0.0
    return log(maxf(float(profit), 1.0)) * (1.0 + bonus + contested)         * maxf(float(profile["profit"]), 0.3) * TIER_STRATEGIC_WEIGHT

## Input schema — snapshot of NATIVE, already checked authorities:
##  location: nonempty source location or "" while in transit
##  fuel_fraction: ShipFuel::fraction() (>=0, finite; no fake refuel)
##  crew_morale: current ShipCrew morale 0..100, or absent when no crew
##  can_rest: true ONLY if Rust's destination search found a viable dock
##  assigned_contract: true if strategy::orders::assigned_contract(...)
##  assigned_plan: candidate from try_plan_contract or null
##  liquidation_buyer: explicit proven real solvent buyer location or ""
##  cargo_used, cargo_capacity: actual physical hold values
##  retrofit: true ONLY if find_retrofit_opportunity returned a plan
##  contract: {name, profit:int, contested:bool, ownership_priority:float,
##             own_strategy:bool, combined_retrofit:bool, retrofit_cost:int}
##  trade: {profit:int, contested:bool, ownership_priority:float,
##          combined_retrofit:bool, retrofit_cost:int}
##  idle_goal: explore|idle_seek_station|idle; chosen by actual world search
##
## Candidates are NOT invented when fields are missing; if the external
## selector hasn't run, no contract/trade is considered. The scores are
## useful only AFTER those source selectors prove their own feasibility.
static func choose_goal(snapshot: Dictionary, profile: Dictionary) -> Dictionary:
    if not Personality.validate(profile):
        return _err("invalid_personality")
    var loc: String = str(snapshot.get("location", ""))
    if loc.is_empty():
        return _decision("idle", TIER_IDLE_FLOOR, [], "no_location")
    var fuel_fraction: Variant = snapshot.get("fuel_fraction", null)
    if not _finite(fuel_fraction):
        return _err("missing_authoritative_fuel_fraction")
    if float(fuel_fraction) < 0.0:
        return _err("invalid_fuel_fraction")
    var candidates: Array = []

    # Rust plan_goal pushes rest and refuel before other tiers.
    if snapshot.has("crew_morale"):
        var morale: Variant = snapshot["crew_morale"]
        if not _finite(morale) or float(morale) < 0.0 or float(morale) > 100.0:
            return _err("invalid_crew_morale")
        if float(morale) < CREW_REST_TRIGGER and bool(snapshot.get("can_rest", false)):
            var urgency: float = clampf(1.0 - float(morale) / CREW_REST_TRIGGER, 0.0, 1.0)
            _push(candidates, "rest_crew",
                urgency * maxf(float(profile["morale"]), 0.2) * TIER_BIO_WEIGHT,
                "biological")

    if float(fuel_fraction) < FUEL_URGENCY_ONSET:
        var fuel_urgency: float = clampf(1.0 - float(fuel_fraction) / FUEL_URGENCY_ONSET,
            0.0, 1.0)
        _push(candidates, "refuel",
            fuel_urgency * maxf(float(profile["safety"]), 0.2) * TIER_BIO_WEIGHT,
            "biological")

    # Assigned contracts bypass housekeeping/strategic/explore. Biological
    # needs still compete against assigned_plan score 35.
    if bool(snapshot.get("assigned_contract", false)):
        var assigned: Variant = snapshot.get("assigned_plan", null)
        if assigned is Dictionary and bool(assigned.get("feasible", false)):
            var assigned_name: String = str(assigned.get("name", ""))
            if assigned_name.is_empty():
                return _err("missing_assigned_goal_name")
            _push(candidates, assigned_name, 35.0, "station_order")
        else:
            _push(candidates, "idle_station_order", TIER_IDLE_FLOOR,
                "station_order")
        return _select(candidates, "assigned_contract")

    var capacity: Variant = snapshot.get("cargo_capacity", null)
    var used: Variant = snapshot.get("cargo_used", null)
    if not (capacity is int) or not (used is int) or int(capacity) < 0:
        return _err("missing_authoritative_cargo")
    if int(used) < 0 or int(used) > int(capacity):
        return _err("invalid_physical_hold")

    var buyer: String = str(snapshot.get("liquidation_buyer", ""))
    if int(used) > 0 and not buyer.is_empty():
        var frac: float = float(used) / float(maxi(int(capacity), 1))
        var scaled: float = 0.5 + clampf(frac, 0.0, 1.0) * 0.5
        _push(candidates, "sell_cargo",
            scaled * maxf(float(profile["profit"]), 0.3) * TIER_HOUSEKEEPING_WEIGHT,
            "housekeeping")

    if bool(snapshot.get("retrofit", false)):
        _push(candidates, "seek_retrofit",
            0.9 * maxf(float(profile["profit"]), 0.3) * TIER_HOUSEKEEPING_WEIGHT,
            "housekeeping")

    # The source may offer ONE viable best contract and ONE trade proposal.
    # Profitability, treaty, liquid buyer, destination, price age and GOAP
    # feasibility are validated by the future Rust-equivalent selectors,
    # NOT manufactured here.
    var contract: Variant = snapshot.get("contract", null)
    if contract is Dictionary:
        if not _valid_commercial_candidate(contract, true):
            return _err("invalid_contract_candidate")
        if bool(contract.get("feasible", false)):
            var cname: String = str(contract["name"])
            var weight: float = float(contract["ownership_priority"])
            var loyalty: float = 1.0 + float(profile["loyalty"])                 if bool(contract.get("own_strategy", false)) else 1.0
            var score: float = score_strategic(int(contract["profit"]), cname,
                profile, bool(contract["contested"])) * weight * loyalty
            if bool(contract.get("combined_retrofit", false)):
                var retrofit_cost: int = int(contract["retrofit_cost"])
                _push(candidates, "fulfill_delivery_with_retrofit",
                    score * 1.2 + score_strategic(int(retrofit_cost / 5),
                        "seek_retrofit", profile, false), "strategic")
            _push(candidates, cname, score, "strategic")

    var trade: Variant = snapshot.get("trade", null)
    if trade is Dictionary:
        if not _valid_commercial_candidate(trade, false):
            return _err("invalid_trade_candidate")
        if bool(trade.get("feasible", false)):
            var score: float = score_strategic(int(trade["profit"]), "trade_run",
                profile, bool(trade["contested"])) * float(trade["ownership_priority"])
            if bool(trade.get("combined_retrofit", false)):
                var retrofit_cost: int = int(trade["retrofit_cost"])
                _push(candidates, "trade_run_with_retrofit",
                    score * 1.2 + score_strategic(int(retrofit_cost / 5),
                        "seek_retrofit", profile, false), "strategic")
            _push(candidates, "trade_run", score, "strategic")

    var idle_name: String = str(snapshot.get("idle_goal", "idle"))
    match idle_name:
        "explore":
            _push(candidates, "explore",
                maxf(float(profile["exploration"]), 0.2) * TIER_EXPLORE_WEIGHT,
                "idle")
        "idle_seek_station":
            _push(candidates, "idle_seek_station", 0.8 * TIER_EXPLORE_WEIGHT,
                "idle")
        "idle":
            _push(candidates, "idle", TIER_IDLE_FLOOR, "idle")
        _:
            return _err("invalid_idle_world_proposal")

    var result: Dictionary = _select(candidates, "native_score")
    if not bool(result.get("ok", false)):
        return result
    # Mining competes against the already chosen standard plan ONLY for
    # miner hulls and only without a held contract; original miner BT
    # must still have been physically validated by mining selector.
    var mine: Variant = snapshot.get("mining_candidate", null)
    if mine is Dictionary and str(snapshot.get("class", "")) == "miner"             and not bool(snapshot.get("active_contract", false)):
        var score_value: Variant = mine.get("score", null)
        if not _finite(score_value) or float(score_value) < 0.0:
            return _err("invalid_mining_score")
        var goal: String = str(mine.get("name", ""))
        if not ["mine_ice", "deliver_mined_ice"].has(goal):
            return _err("invalid_mining_action")
        if bool(mine.get("feasible", false)) and float(score_value) > float(result["score"]):
            result["name"] = goal
            result["score"] = float(score_value)
            result["source"] = "mining_native"
    return result

static func _valid_commercial_candidate(candidate: Dictionary, is_contract: bool) -> bool:
    if is_contract and (not (candidate.get("name", null) is String)             or str(candidate["name"]).is_empty()):
        return false
    if not (candidate.get("profit", null) is int):
        return false
    var priority: Variant = candidate.get("ownership_priority", null)
    if not _finite(priority) or float(priority) < 0.0:
        return false
    if not (candidate.get("contested", null) is bool):
        return false
    if not (candidate.get("feasible", null) is bool):
        return false
    if bool(candidate.get("combined_retrofit", false)) and not (candidate.get("retrofit_cost", null) is int):
        return false
    return true

## Rust Iterator::max_by keeps the LAST equal candidate; the
## source comment says "earliest-pushed", but we follow executable
## Rust semantics instead. This is not the generic utility best_action,
## which uses a strict > and keeps FIRST on ties.
static func _select(candidates: Array, reason: String) -> Dictionary:
    if candidates.is_empty():
        return _err("no_goal_candidates")
    var selected: Dictionary = candidates[0]
    for candidate in candidates:
        if float(candidate["score"]) >= float(selected["score"]):
            selected = candidate
    return _decision(str(selected["name"]), float(selected["score"]),
        candidates, reason)

static func _decision(name: String, score: float, candidates: Array,
        why: String) -> Dictionary:
    return {"ok": true, "name": name, "score": score,
        "source": why, "requires_bt_planner": true,
        "ranked_candidates": candidates.duplicate(true)}

static func _push(target: Array, name: String, score: float, tier: String) -> void:
    target.append({"name": name, "score": score, "tier": tier})

static func _finite(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))

static func _err(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
