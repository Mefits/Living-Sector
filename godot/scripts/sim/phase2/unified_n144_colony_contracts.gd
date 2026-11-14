extends RefCounted
## Frozen Rust strategy/{colony.rs::proposals/commission,coordination.rs,
## director.rs::retain_or_switch}: one approved unfinished colony site,
## one real N134 head permission, one N104 prepaid PASSENGER order.
## Do not post Metals until source N97/N15 marketless colony construction
## material transfer is implemented. Not a second head/world/ledger.
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Board = preload("res://scripts/sim/economy/contract_board.gd")
const N134Cycle = preload("res://scripts/sim/phase1/n134_coordination_cycle.gd")
const N134Head = preload("res://scripts/sim/phase1/n134_coordination_head.gd")
const N134Policy = preload("res://scripts/sim/phase1/n134_coordination_policy.gd")
const Commission = preload("res://scripts/sim/phase1/n151_native_colony_commission.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")

const PROJECT_TAG: String = "strategy.colony.v1"
const DIRECTOR_SETTLERS: int = 50
const PASSENGER_PAYMENT_PER_HEAD: int = 80
const STARTUP_CAPITAL: int = 20000
const SUBSIDY_FLOOR: int = 5000
const WAGE_PER_SHIFT: int = 1
const COMMITMENT_SUPERIORITY: float = 1.20
const COMMITMENT_CONFIRMATIONS: int = 2

static func _error(why: String) -> Dictionary:
    return {"ok": false, "reason": why}

static func _target(goal: Dictionary) -> String:
    # The existing N134Policy port uses the plain live source
    # destination/target key; never introduce a competing address key.
    return str(goal.get("target", goal.get("destination", "")))

static func _available_ship(world: Dictionary, faction: String, qty: int) -> bool:
    for raw in world.get("ships", {}).values():
        var ship: Dictionary = raw
        if str(ship.get("faction_id", "")) != faction or float(ship.get("fuel", 0.0)) <= 0.0:
            continue
        if int(Catalog.spec(str(ship.get("class", ""))).get("passenger_capacity", 0)) >= qty:
            return true
    return false

## Source active-site branch of colony::proposals. The original source
## tests paid work, population and N104 outstanding before any new post.
static func active_site(world: Dictionary, graph: RefCounted,
        faction: String, tick: int, multiplier: int) -> Dictionary:
    if graph == null or tick < 1 or multiplier < 1 or not world.get("faction_treasuries", {}).has(faction):
        return _error("n144_missing_original_strategy_world")
    var ids: Array = world.get("construction_sites", {}).keys()
    ids.sort()
    var site: Dictionary = {}
    for id in ids:
        var raw: Dictionary = world["construction_sites"][id]
        if str(raw.get("faction_id", "")) == faction and not bool(raw.get("completed", false)) and raw.get("labor", {}) is Dictionary and raw["labor"].get("colony_source", null) != null:
            site = raw
            break
    if site.is_empty():
        return {"ok": true, "ready": false, "reason": "no_active_native_colony_site"}
    var site_id: String = str(site["id"])
    # Rust native execution retains its own prepaid sequence. Do not
    # commission N144 over an outstanding HTN/N98/N121 plan.
    var native: Dictionary = world.get("native_planner_records", {}).get(faction, {})
    if str(native.get("status", "")) in [
            "n98_planned_not_dispatched", "n121_active"]:
        return {"ok": true, "ready": false,
            "reason": "outstanding_native_plan_retained"}
    var source: String = str(site["labor"]["colony_source"])
    var dest: String = str(site["location_name"])
    var plan: Dictionary = {"site_id": site_id, "faction_id": faction,
        "source": source, "destination": dest, "body_id": str(site["body_id"]),
        "goal": {"goal_id": "found_colony", "commodity": "metals",
            "destination": dest, "shortage_ticks": 0, "score": 0.0},
        "reason": "ready", "passenger": true}
    if not world.get("markets", {}).has(source) or world.get("markets", {}).has(dest):
        plan["reason"] = "n144_invalid_source_or_completed_colony"
    elif not graph.has_location(dest) or not graph.shortest_path(source, dest).get("reachable", false):
        plan["reason"] = "n144_unreachable_original_site"
    var proof: Dictionary = world.get("construction_receipts", {}).get(
        "n151_colony_dock:" + site_id, {})
    var dock: Dictionary = world.get("facilities", {}).get(
        str(proof.get("facility_id", "")), {})
    if str(proof.get("kind", "")) != "colony_dock_prepared" or (
            str(dock.get("type", "")) != "construction_dock" or
            str(dock.get("location", "")) != dest or
            str(dock.get("faction", "")) != faction):
        plan["reason"] = "n144_requires_original_prepared_colony_dock"
    var settlers: int = DIRECTOR_SETTLERS if world.get("research_directors", {}).has(faction) else Commission.SETTLERS
    var settled: bool = false
    var valid_origin: bool = false
    for raw in world.get("populations", {}).values():
        var p: Dictionary = raw
        if str(p.get("faction", "")) != faction:
            continue
        if str(p.get("location", "")) == dest and int(p.get("count", 0)) >= settlers:
            settled = true
        if str(p.get("location", "")) == source and int(p.get("count", 0)) >= settlers + Commission.SETTLERS:
            valid_origin = true
    plan["quantity"] = settlers
    plan["cost"] = settlers * PASSENGER_PAYMENT_PER_HEAD
    if settled:
        plan["passenger"] = false
        plan["quantity"] = mini(200, maxi(0,
            int(site.get("progress_required", 0)) - int(site.get("progress_delivered", 0))))
        plan["cost"] = 10000
        plan["reason"] = "n144_original_metals_marketless_delivery_pending"
    elif not valid_origin:
        plan["reason"] = "insufficient_settlers"
    else:
        var boards: Dictionary = world.get("contract_board", {}).get("contracts", {})
        for c in boards.values():
            if str(c.get("requestor_id", "")) == Schema.faction_account(faction) and (
                    str(c.get("destination_location", "")) == dest and
                    str(c.get("status", "")) not in ["paid", "expired"]):
                plan["reason"] = "colony_contract_in_progress"
                break
        var treasury: int = int(world["faction_treasuries"][faction])
        var labor: Dictionary = site["labor"]
        var reserve: int = STARTUP_CAPITAL + maxi(0, int(labor.get("required", 0)) -
            int(labor.get("completed", 0))) * WAGE_PER_SHIFT
        if treasury - SUBSIDY_FLOOR < plan["cost"] + reserve:
            plan["reason"] = "insufficient_colony_budget"
        elif not _available_ship(world, faction, settlers):
            plan["reason"] = "no_passenger_transport"
    plan["ready"] = str(plan["reason"]) == "ready"
    return {"ok": true, "ready": bool(plan["ready"]), "reason": str(plan["reason"]),
        "plan": plan}

## Exact N113 director retain_or_switch semantics over the ORIGINAL P1
## N134Policy candidate ranking; memory remains on the canonical Director.
## No artificial command or first-cycle strategy override.
static func _choose_strategy(candidates: Array, old: Dictionary, tick: int,
        survival: bool, funded: bool) -> Dictionary:
    var viable: Array = []
    for row in candidates:
        if row is Dictionary and bool(row.get("available", false)) and (
                is_finite(float(row.get("score", 0.0))) and float(row["score"]) > 0.0):
            viable.append(row)
    if viable.is_empty():
        return {"choice": {}, "memory": old.duplicate(true)}
    var best: Dictionary = viable[0]
    var previous: Dictionary = {}
    for row in viable:
        if str(row.get("action", "")) == str(old.get("kind", "")) and str(row.get("target", "")) == str(old.get("target", "")):
            previous = row
            break
    var memory: Dictionary = old.duplicate(true)
    var chosen: Dictionary = best
    var reason: String = "previous_goal_unavailable"
    if not previous.is_empty():
        chosen = previous
        reason = "viable_commitment_retained"
        if str(best.get("action", "")) != str(previous.get("action", "")) or str(best.get("target", "")) != str(previous.get("target", "")):
            if funded and str(previous.get("action", "")) == "supply":
                reason = "outstanding_native_plan_retained"
            elif survival and str(best.get("action", "")) == "supply":
                chosen = best
                reason = "urgent_life_support"
            elif float(best.get("score", 0.0)) < float(previous.get("score", 0.0)) * COMMITMENT_SUPERIORITY:
                reason = "alternative_not_strong_enough"
            else:
                var old_pending: Dictionary = memory.get("pending", {}) if memory.get("pending") is Dictionary else {}
                var same_pending: bool = str(old_pending.get("kind", "")) == str(best.get("action", "")) and str(old_pending.get("target", "")) == str(best.get("target", ""))
                var consecutive: int = int(old_pending.get("consecutive_cycles", 0)) + 1 if same_pending else 1
                if consecutive >= COMMITMENT_CONFIRMATIONS:
                    chosen = best
                    reason = "sustained_higher_utility"
                else:
                    memory["pending"] = {"kind": str(best["action"]),
                        "target": str(best["target"]), "consecutive_cycles": consecutive,
                        "first_seen_tick": int(old_pending.get("first_seen_tick", tick)) if same_pending else tick}
                    reason = "alternative_pending_confirmation"
    if str(chosen.get("action", "")) != str(memory.get("kind", "")) or str(chosen.get("target", "")) != str(memory.get("target", "")):
        memory["since"] = tick
    memory["kind"] = str(chosen["action"])
    memory["target"] = str(chosen.get("target", ""))
    memory["score"] = float(chosen["score"])
    memory["reason"] = reason
    if reason != "alternative_pending_confirmation":
        memory["pending"] = null
    return {"choice": {"action": str(chosen["action"]),
        "target": str(chosen.get("target", "")), "reason": reason},
        "memory": memory}

## Derive authorization from the existing N134 comparator, N113
## Director hysteresis, N134 HeadDecision and ORIGINAL exact grant.
## The caller cannot pass arbitrary head_authorized=true.
static func approval(world: Dictionary, baseline: Dictionary,
        active: Dictionary, faction: String, tick: int, multiplier: int) -> Dictionary:
    if not active.get("ok", false):
        return active
    var plan: Dictionary = active.get("plan", {})
    if plan.is_empty() or not active.get("ready", false):
        return {"ok": true, "authorized": false,
            "reason": str(active.get("reason", "colony_not_ready"))}
    var head: Dictionary = baseline.get("head", {})
    if head.is_empty():
        return _error("n144_missing_original_n134_comparison")
    var commander: Dictionary = world.get("research_directors", {}).get(faction, {})
    var contracts: Array = []
    for c in world.get("contract_board", {}).get("contracts", {}).values():
        var row: Dictionary = c.duplicate(true)
        if str(row.get("requestor_id", "")) == Schema.faction_account(faction):
            row["requestor_id"] = faction
        # P1 N134Policy expects the ORIGINAL Rust enum case and the
        # prepaid Funding struct, not N104's storage representation.
        var phase: String = str(row.get("status", ""))
        if not phase.is_empty():
            row["status"] = phase.substr(0, 1).to_upper() + phase.substr(1)
        row["funding"] = {"reserved": int(c.get("reserved", 0))}
        contracts.append(row)
    var comparison: Dictionary = {"goal": head.get("problem", {}).duplicate(true),
        "alternatives": head.get("alternatives", []).duplicate(true),
        "selected": str(head.get("selected_option", "wait"))}
    var memory: Dictionary = commander.get("strategic", {}) if commander.get("strategic") is Dictionary else {}
    var inputs: Dictionary = {"colony": plan, "faction_id": faction,
        "native_active": false, "contracts": contracts,
        "native_target": _target(head.get("problem", {}))}
    var computed_score: float = 0.0
    if comparison["selected"] != "wait":
        for alt in comparison["alternatives"]:
            if str(alt.get("action", "")) == str(comparison["selected"]) and (
                    alt.get("estimated_net_value", null) != null):
                computed_score = maxf(computed_score, float(alt["estimated_net_value"]))
    inputs["native_option_score"] = computed_score
    # Only a real, still funded research target counts as a competing
    # strategic option. Actual paid research stays owned by N143.
    inputs["research_ready"] = commander.get("research", null) != null and (
        int(commander.get("research_required", 0)) > 0)
    var view: Dictionary = commander.duplicate(true)
    var profile: Dictionary = commander.get("profile", {})
    view["science"] = float(profile.get("science", 0.0))
    view["expansion"] = float(profile.get("expansion", 0.0))
    view["strategic_kind"] = str(memory.get("kind", ""))
    view["strategic_target"] = str(memory.get("target", ""))
    var decision: Dictionary = {}
    if not commander.is_empty():
        var initial: Dictionary = N134Head.preview(
            {"treasury": int(world["faction_treasuries"][faction])},
            comparison, tick, multiplier, false)
        initial = N134Head.append_colony_proposal(initial, plan, true)
        var ranked: Dictionary = N134Policy.build_candidates(initial, view, inputs)
        var switch: Dictionary = _choose_strategy(
            ranked.get("candidates", []), memory, tick,
            bool(ranked.get("survival", false)),
            bool(ranked.get("funded_order", false)))
        decision = switch.get("choice", {})
        memory = switch.get("memory", {})
    var cycle = N134Cycle.new()
    var preview: Dictionary = cycle.preview_cycle(tick, multiplier, {
        "mode": "Execute", "native_execution_enabled": false,
        "factions": {faction: {
            "view": {"treasury": int(world["faction_treasuries"][faction])},
            "comparison": comparison, "commander": view,
            "colony": plan, "candidate_inputs": inputs,
            "director_choice": decision}},
        "contracts": contracts})
    if not preview.get("ok", false):
        return preview
    var real_head: Dictionary = preview.get("heads", {}).get(faction, {})
    var permitted: bool = str(real_head.get("selected_option", "")) == "supply_colony" and (
        str(real_head.get("selected_administrator", "")) == "construction" and
        N134Head.authorized(true, preview.get("grants", {}), faction,
            "construction", plan["goal"]))
    return {"ok": true, "authorized": permitted,
        "head": real_head, "memory": memory,
        "reason": str(real_head.get("reason", "n144_head_wait"))}

## A single N9 ledger+one N104 Board post. Only the exact source-approved
## passenger plan may reach this code. N39 validates all invariants and
## publishes both together; this stage cannot mutate N39 itself.
static func stage_paid_passengers(world: Dictionary, bank: Dictionary,
        active: Dictionary, faction: String, tick: int, multiplier: int,
        graph: RefCounted) -> Dictionary:
    if not active.get("ready", false) or not (active.get("plan") is Dictionary):
        return _error("n144_no_current_source_paid_passenger_plan")
    var plan: Dictionary = active["plan"]
    if not plan.get("passenger", false):
        return _error("n144_metal_contract_requires_original_n97_colony_cargo")
    var src: String = str(plan["source"])
    var dst: String = str(plan["destination"])
    var qty: int = int(plan["quantity"])
    var cost: int = int(plan["cost"])
    if qty not in [Commission.SETTLERS, DIRECTOR_SETTLERS] or cost != qty * PASSENGER_PAYMENT_PER_HEAD:
        return _error("n144_invalid_original_passenger_terms")
    var distance: Dictionary = graph.shortest_path(src, dst)
    if not distance.get("reachable", false):
        return _error("n144_original_route_unavailable")
    var lifespan: int = Commission.CONSTRUCTION_LIFESPAN_BASE
    if world.get("research_directors", {}).has(faction):
        lifespan = maxi(lifespan, int(distance.get("distance", 0)) * 100 + 1200)
    lifespan *= multiplier
    if lifespan <= 0 or tick > 9223372036854775807 - lifespan:
        return _error("n144_invalid_original_lifespan")
    var ledger := Ledger.new()
    if not ledger.restore(bank):
        return _error("n144_missing_canonical_n9")
    var board := Board.new(ledger)
    if not board.restore(world.get("contract_board", {})):
        return _error("n144_missing_canonical_n104")
    var cid: String = "n144/colony/passenger/" + str(plan["site_id"]) + "/" + str(tick)
    var escrow: String = "escrow:" + cid
    if not ledger.register_empty_account(escrow):
        return _error("n144_duplicate_n104_escrow")
    var payer: String = Schema.faction_account(faction)
    var paid: Dictionary = board.post(cid, "passenger", payer,
        escrow, "food", qty, src, dst, cost, tick, tick + lifespan, "faction")
    if not paid.get("ok", false):
        return paid
    var snapshot: Dictionary = board.snapshot()
    snapshot["contracts"][cid]["mission_category"] = Commission.PROJECT_TAG
    snapshot["contracts"][cid]["colony_site_id"] = str(plan["site_id"])
    snapshot["contracts"][cid]["faction_id"] = faction
    if not board.restore(snapshot):
        return _error("n144_prepaid_metadata_rejected")
    var staged: Dictionary = world.duplicate(true)
    staged["contract_board"] = board.snapshot()
    staged["escrow_balances"][escrow] = ledger.balance(escrow)
    staged["faction_treasuries"][faction] = ledger.balance(payer)
    return {"ok": true, "world": staged,
        "ledger_snapshot": ledger.snapshot(), "contract_id": cid,
        "site_id": str(plan["site_id"]), "quantity": qty,
        "money_debited": cost, "escrow_account": escrow,
        "status": "N144_ORIGINAL_PAID_FOUNDING_PASSENGERS"}
