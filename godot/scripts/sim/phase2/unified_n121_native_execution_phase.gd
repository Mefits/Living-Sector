extends RefCounted
## Frozen Rust strategy/planning/native_execution.rs N121 -> the ONLY
## P2 N39/N104/N9 domain. This is a read-only bridge, NOT another board.
const Snapshot = preload("res://scripts/sim/phase2/unified_native_hybrid_planning.gd")
const Dispatch = preload("res://scripts/port/n121_native_dispatch.gd")
const N98 = preload("res://scripts/sim/phase1/n98_plan_ledger.gd")
const N121Receipts = preload("res://scripts/port/n121_native_receipts.gd")

## Source Dispatch.preflight takes the original ECS projection, whereas
## N39 owns keyed facilities, escrow accounts and the real N104 board.
## Derive the source shape from the CURRENT World at dispatch-time, never
## from a hypothetical planner or an earlier captured market price.
static func paid_delivery_quote(world: Dictionary, faction: String,
        action: Dictionary, dispatch_key: String, tick: int, multiplier: int,
        graph: RefCounted) -> Dictionary:
    if graph == null or not (world.get("markets") is Dictionary) or not (
            world.get("ships") is Dictionary):
        return {"ok": false, "reason": "n121_missing_real_navigation_or_market"}
    var captured: Dictionary = Snapshot.capture(world, faction, tick)
    if not captured.get("ok", false):
        return captured
    var original: Dictionary = captured["snapshot"]
    var source: String = str(action.get("source_id", ""))
    var destination: String = str(action.get("destination_id", ""))
    if source.is_empty() or source == destination or not graph.has_location(
            source) or not graph.has_location(destination):
        return {"ok": false, "reason": "n121_missing_original_route"}
    var route: Dictionary = graph.shortest_path(source, destination)
    if not route.get("reachable", false) or not (route.get("locations") is Array):
        return {"ok": false, "reason": "n121_unreachable_native_route"}
    var hops: int = maxi(0, route["locations"].size() - 1)
    var projected: Dictionary = {"factions": {}, "global_markets": [],
        "ships": {}, "nav_shortest_distance": {}}
    var accounts: Dictionary = world.get("faction_treasuries", {})
    var faction_ids: Array = accounts.keys()
    faction_ids.sort()
    for id in faction_ids:
        projected["factions"][id] = {"treasury": int(accounts[id])}
    var locations: Array = world["markets"].keys()
    locations.sort()
    for loc in locations:
        var market: Dictionary = world["markets"][loc]
        projected["global_markets"].append({
            "market_id": str(market.get("id", "")),
            "location_id": str(loc),
            "facility_id": str(market.get("owner", ""))})
    for ship_id in world["ships"]:
        var ship: Dictionary = world["ships"][ship_id].duplicate(true)
        # Rust's Option<Entity> NONE is null, not Godot's old empty
        # active_contract_id. This conversion does not mutate the ship.
        if str(ship.get("active_contract_id", "")).is_empty():
            ship["active_contract_id"] = null
        projected["ships"][ship_id] = ship
    projected["nav_shortest_distance"][source + "\u001f" + destination] = hops
    var board: Dictionary = world.get("contract_board", {})
    var quote: Dictionary = Dispatch.preflight(projected, {
        "contracts": board.get("contracts", {})
    }, original, faction, action, dispatch_key, tick, multiplier)
    if not quote.get("ok", false):
        return quote
    # One physical N104 destination/commodity promise at a time, even
    # if an older N135 order used a facility payer instead of a faction.
    for contract in board.get("contracts", {}).values():
        if not (contract is Dictionary):
            return {"ok": false, "reason": "n121_invalid_canonical_contract"}
        if str(contract.get("status", "")) in ["paid", "expired"]:
            continue
        if (str(contract.get("destination_location", "")) == destination
                and str(contract.get("commodity", "")) ==
                str(action.get("commodity", ""))):
            return {"ok": false, "reason": "n121_existing_real_destination_order"}
    return {"ok": true, "quote": quote, "source_snapshot": original,
        "source_path": route["locations"].duplicate(true),
        "native_dispatch_authority": "n121_source_preflight_on_n39_world"}

## The source N98 action_id is not an invented contract. Only the
## matching currently active native plan can request this step.
static func action_for_step(plan: Dictionary, gate: Dictionary) -> Dictionary:
    if str(gate.get("kind", "")) != "ready":
        return {"ok": false, "reason": "n121_not_ready"}
    var ledger: Dictionary = plan.get("ledger", {})
    if N98.next_gate(ledger) != gate:
        return {"ok": false, "reason": "n121_stale_source_plan_gate"}
    var action: Dictionary = N121Receipts.action_for_step(
        plan, str(gate.get("step_id", "")))
    if not action.get("ok", false):
        return action
    return action

## Paid only if the source N104 actual settlement and N9 immutable
## receipts exist; the N15 load/unload operations are never simulated.
static func native_delivery_receipt(world: Dictionary, bank: Dictionary,
        faction: String, plan: Dictionary, gate: Dictionary,
        tick: int) -> Dictionary:
    var cid: String = str(gate.get("native_order_id", ""))
    var step: String = str(gate.get("step_id", ""))
    var contracts: Dictionary = world.get("contract_board", {}).get(
        "contracts", {})
    var meta: Dictionary = world.get("native_htn_contracts", {}).get(cid, {})
    if meta.is_empty() or not contracts.has(cid):
        return {"ok": true, "receipt": null,
            "reason": "n121_native_order_not_found"}
    var c: Dictionary = contracts[cid]
    if (str(meta.get("faction_id", "")) != faction or
            str(meta.get("plan_id", "")) !=
            str(plan.get("ledger", {}).get("plan_id", "")) or
            str(meta.get("step_id", "")) != step or
            str(c.get("requestor_id", "")) != "faction/" + faction or
            str(c.get("native_htn_key", "")) !=
            str(meta.get("dispatch_key", "")) or
            str(c.get("funding_source", "")) != "faction"):
        return {"ok": false, "reason": "n121_native_receipt_identity_changed"}
    if not (bank.get("receipts") is Dictionary):
        return {"ok": false, "reason": "n121_no_original_ledger_receipts"}
    if not bank["receipts"].has("contract:" + cid + ":post"):
        return {"ok": false, "reason": "n121_unfunded_native_contract"}
    var outcome: String = ""
    var status: String = str(c.get("status", ""))
    match status:
        "posted":
            outcome = "submitted"
        "accepted", "picked_up", "delivered":
            outcome = "running"
        "paid":
            var paid: String = "contract:" + cid + ":payout"
            var load: String = "contract:" + cid + ":load"
            var unload: String = "contract:" + cid + ":unload"
            var cargo: Dictionary = world.get("cargo_receipts", {})
            if not bank["receipts"].has(paid) or not cargo.has(load) or not cargo.has(unload):
                return {"ok": false, "reason": "n121_missing_paid_physical_delivery"}
            for physical in [cargo[load], cargo[unload]]:
                if not (physical is Dictionary) or physical.get("ok", false) != true or str(physical.get("ship_id", "")) != str(c.get("fulfiller_id", "")):
                    return {"ok": false, "reason": "n121_forbidden_synthetic_delivery"}
            if (str(cargo[load].get("action", "")) != "load" or str(cargo[unload].get("action", "")) != "unload" or
                    str(cargo[load].get("location_id", "")) != str(c.get("source_location", "")) or
                    str(cargo[unload].get("location_id", "")) != str(c.get("destination_location", ""))):
                return {"ok": false, "reason": "n121_wrong_physical_delivery_locations"}
            outcome = "succeeded"
        "expired":
            var escrow: String = str(c.get("escrow_account", ""))
            if int(world.get("escrow_balances", {}).get(escrow, -1)) != 0 or int(c.get("reserved", -1)) != 0 or not bank["receipts"].has("contract:" + cid + ":refund"):
                return {"ok": true, "receipt": null,
                    "reason": "n121_wait_real_n104_refund"}
            outcome = "failed"
        _:
            return {"ok": false, "reason": "n121_unrecognized_real_contract_status"}
    var phase: String = ""
    for row in plan.get("ledger", {}).get("steps", []):
        if str(row.get("step", {}).get("step_id", "")) == step:
            phase = str(row.get("phase", ""))
            break
    if phase.is_empty():
        return {"ok": false, "reason": "n121_missing_original_step"}
    if phase == "running" and outcome == "submitted":
        return {"ok": true, "receipt": null, "reason": "n121_no_receipt_downgrade"}
    return {"ok": true, "receipt": {
        "plan_id": str(plan.get("ledger", {}).get("plan_id", "")),
        "step_id": step, "native_order_id": cid,
        "status": outcome, "reason_code": "native_contract_" + status,
        "tick": tick}, "reason": "n121_real_canonical_contract_observed"}
