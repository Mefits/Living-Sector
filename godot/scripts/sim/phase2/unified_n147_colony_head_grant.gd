extends RefCounted
## Frozen Rust strategy/coordination.rs::run_cycle (migrants only).
## A source N147 ready offer is NOT a faction grant. In the original ECS
## the actual Head must choose "migrate_colony" before N92::commission
## posts a paid N104 Passenger order. This is a pure read-only grant
## validation/proposal: the one N39 World/N9/ContractBoard owns Apply.
const StrategicSwitchAdvantage: float = 1.20
const SourceMigrationScore: float = 60.0

static func _fail(why: String) -> Dictionary:
    return {"ok": false, "reason": why}

static func authorize(world: Dictionary, faction: String, ready: Dictionary,
        baseline: Dictionary, tick: int) -> Dictionary:
    if tick <= 0 or faction.is_empty() or not (
            world.get("faction_treasuries") is Dictionary) or not (
            world.get("research_directors") is Dictionary) or not (
            world.get("contract_board") is Dictionary):
        return _fail("n147_missing_source_head_authority")
    if not world["faction_treasuries"].has(faction) or not (
            world["research_directors"].get(faction) is Dictionary):
        return _fail("n147_no_actual_faction_director")
    if ready.get("faction_id", null) != faction or (
            str(ready.get("status", "")) != "N147_PREPARED_NOT_POSTED"):
        return _fail("n147_untrusted_or_old_migration_offer")
    var destination: String = str(ready.get("destination", ""))
    var origin: String = str(ready.get("source", ""))
    var passengers: int = int(ready.get("quantity", -1))
    var price: int = int(ready.get("payment", -1))
    if destination.is_empty() or origin.is_empty() or origin == destination or (
            passengers <= 0 or price <= 0):
        return _fail("n147_bad_physical_migration_terms")
    if int(baseline.get("observed_tick", -1)) != tick:
        return _fail("n147_head_not_from_this_decision_tick")
    var choice: String = str(baseline.get("selected_option", ""))
    # A real already-funded construction, supply, research or native-plan
    # decision cannot silently be displaced by the ready migration offer.
    if choice not in ["wait", "migrate_colony"] or str(
            baseline.get("reason", "")) in [
            "already_commissioned_this_tick",
            "outstanding_native_plan_retained"]:
        return {"ok": true, "authorized": false,
            "reason": "n147_other_original_head_grant_retained"}
    if choice == "wait" and not str(baseline.get(
            "selected_administrator", "")).is_empty():
        return {"ok": true, "authorized": false,
            "reason": "n147_wait_head_has_another_grant"}
    var record: Dictionary = world.get("native_planner_records", {}).get(
        faction, {})
    if str(record.get("status", "")) in [
            "n98_planned_not_dispatched", "n121_active"] or (
            world.get("native_execution", {}).get(
                "active", {}).has(faction)):
        return {"ok": true, "authorized": false,
            "reason": "n147_one_existing_native_plan_first"}
    var contracts: Variant = world["contract_board"].get("contracts", null)
    if not (contracts is Dictionary):
        return _fail("n147_missing_original_n104_contracts")
    for c in contracts.values():
        if not (c is Dictionary):
            return _fail("n147_invalid_real_contract")
        if str(c.get("requestor_id", "")) in [
                "faction/" + faction, faction] and str(
                c.get("status", "")) not in ["paid", "expired"] and (
                int(c.get("posted_at_tick", -1)) == tick or str(
                c.get("mission_category", "")) in [
                "strategy.colony.v1", "strategy.colony.workforce.v1",
                "strategy.construction.v1"]):
            return {"ok": true, "authorized": false,
                "reason": "n147_existing_original_funded_head_commit"}
    var director: Dictionary = world["research_directors"][faction]
    var old: Variant = director.get("strategic", {})
    if not (old is Dictionary):
        return _fail("n147_invalid_retained_director_strategy")
    var memory: Dictionary = old
    var incumbent: String = str(memory.get("kind", ""))
    var current_target: String = str(memory.get("target", ""))
    # Rust Director::retain_or_switch keeps a viable existing commitment
    # until 1.2x superiority over TWO actual strategic cycles. This small
    # N147 branch must NOT invent an extra Director vote and override
    # an unrelated already selected supply/research/expansion strategy.
    if not incumbent.is_empty() and (
            incumbent != "migrate" or current_target != destination):
        return {"ok": true, "authorized": false,
            "reason": "n147_source_director_strategy_not_migration"}
    var staged: Dictionary = memory.duplicate(true)
    var changing: bool = incumbent != "migrate" or current_target != destination
    staged["kind"] = "migrate"
    staged["target"] = destination
    staged["score"] = SourceMigrationScore
    staged["since"] = tick if changing else int(staged.get("since", tick))
    staged["reason"] = "colony_workforce_needed" if changing else (
        "viable_commitment_retained")
    staged["pending"] = null
    var head: Dictionary = baseline.duplicate(true)
    head["selected_option"] = "migrate_colony"
    head["selected_administrator"] = ""
    head["problem"] = {}
    head["planned_spend"] = price
    head["reason"] = "colony_workforce_needed"
    return {"ok": true, "authorized": true,
        "faction_id": faction, "tick": tick, "head": head,
        "strategy": staged, "ready": ready.duplicate(true),
        "money_spent": 0, "source": "rust_n92_migration_only_after_one_n134_head"}
