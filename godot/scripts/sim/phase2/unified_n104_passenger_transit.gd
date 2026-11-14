extends RefCounted
## P2 N104/N126/N147: canonical passenger transactions for the ONE N39
## World, N9 ledger and N104 ContractBoard. Rust references:
## sim_server/engine/transactions.rs::{embark,deliver}, strategy/colony_development.rs.
## A passenger is never cargo "food"; no market stock moves here.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Board = preload("res://scripts/sim/economy/contract_board.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Seats = preload("res://scripts/port/n104_passenger_contracts.gd")
const Planner = preload("res://scripts/sim/phase1/n147_native_colony_migration_planner.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const Goap = preload("res://scripts/sim/ships/ai/native_goap_planner.gd")
const Plans = preload("res://scripts/sim/phase1/n153_native_ship_bt_planning.gd")
const ShipPlanning = preload("res://scripts/sim/phase2/unified_ship_ai_planner.gd")
const NativeN153 = preload("res://scripts/sim/phase1/n153_native_ship_contract_selection.gd")
const SourceN147 = preload("res://scripts/sim/phase2/unified_n147_colony_migration_observer.gd")

class PassengerEvidence extends RefCounted:
    var receipts: Dictionary = {}

static func _reject(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}

static func _open(world: Dictionary, bank: Dictionary) -> Dictionary:
    if not (world.get("contract_board") is Dictionary and
            world.get("escrow_balances") is Dictionary and
            world.get("ships") is Dictionary and
            world.get("populations") is Dictionary):
        return _reject("missing_canonical_passenger_authority")
    var ledger := Ledger.new()
    if not ledger.restore(bank):
        return _reject("invalid_one_n9_ledger")
    var board := Board.new(ledger)
    if not board.restore(world["contract_board"]):
        return _reject("invalid_one_n104_board")
    var evidence := PassengerEvidence.new()
    evidence.receipts = world.get("passenger_receipts", {}).duplicate(true)
    board.bind_physical_cargo(evidence)
    return {"ok": true, "ledger": ledger, "board": board, "evidence": evidence}

static func _valid_dock(world: Dictionary, ship: Dictionary, location: String) -> bool:
    if str(ship.get("location", "")) != location or not (ship.get("transit", {}) as Dictionary).is_empty():
        return false
    var fid: String = str(ship.get("docked_at", ""))
    var facility: Dictionary = world.get("facilities", {}).get(fid, {})
    if facility.is_empty() or bool(facility.get("abandoned", false)):
        return false
    return str(facility.get("location", "")) == location and (
        fid == str(world.get("markets", {}).get(location, {}).get("owner", "")))

static func _resident(world: Dictionary, faction: String,
        location: String, minimum: int) -> String:
    var ids: Array = world.get("populations", {}).keys()
    ids.sort()
    for pid in ids:
        var p: Dictionary = world["populations"][pid]
        if str(p.get("location", "")) == location and str(p.get("faction", "")) == faction and int(p.get("count", 0)) >= minimum:
            return str(pid)
    return ""

static func _commit(staged: Dictionary, ledger: Variant,
        board: Variant, old_bank: Dictionary, tick: int,
        status: String, cid: String, sid: String) -> Dictionary:
    staged["contract_board"] = board.snapshot()
    var validation: String = Schema.validate(staged)
    if not validation.is_empty():
        return _reject("n104_passenger_world_" + validation)
    if ledger.total() != _sum_money(old_bank.get("balances", {})):
        return _reject("n104_passenger_conservation_failed")
    var accounts: Dictionary = Schema.accounts(staged)
    var actual: Dictionary = ledger.snapshot().get("balances", {})
    if accounts.size() != actual.size():
        return _reject("n104_passenger_account_count_mismatch")
    for account in accounts:
        if not actual.has(account) or int(actual[account]) != int(accounts[account]):
            return _reject("n104_passenger_money_divergence:" + str(account))
    return {"ok": true, "status": status, "world": staged,
        "ledger_snapshot": ledger.snapshot(), "contract_id": cid,
        "ship_id": sid, "tick": tick}

static func _sum_money(balances: Dictionary) -> int:
    var total: int = 0
    for value in balances.values():
        total += int(value)
    return total

## This is invoked only with a real N92/N147 ready plan from the existing
## read-only source bridge. Revalidate against the CURRENT World before debit.
static func post_migration(world: Dictionary, bank: Dictionary,
        ready: Dictionary, tick: int, mult: int, graph: RefCounted) -> Dictionary:
    if tick < 1 or mult < 1 or graph == null:
        return _reject("n147_invalid_real_phase")
    var faction: String = str(ready.get("faction_id", ""))
    var source: String = str(ready.get("source", ""))
    var dest: String = str(ready.get("destination", ""))
    var quantity: int = int(ready.get("quantity", 0))
    var price: int = int(ready.get("payment", 0))
    if faction.is_empty() or source.is_empty() or dest.is_empty() or source == dest or (
            quantity <= 0 or quantity > Planner.MAX_MIGRATION_PARTY or
            price != quantity * Planner.PASSENGER_PAYMENT_PER_HEAD):
        return _reject("n147_invalid_source_terms")
    if str(ready.get("status", "")) != "N147_PREPARED_NOT_POSTED":
        return _reject("n147_not_source_authorized")
    if not bool(graph.shortest_path(source, dest).get("reachable", false)):
        return _reject("n147_no_directed_route")
    if not world.get("markets", {}).has(source) or not world.get("markets", {}).has(dest):
        return _reject("n147_missing_real_colony_market")
    if _resident(world, faction, source, quantity + Planner.MIN_SOURCE_RESERVE).is_empty() or _resident(world, faction, dest, 0).is_empty():
        return _reject("n147_missing_real_households")
    for c in world.get("contract_board", {}).get("contracts", {}).values():
        if str(c.get("contract_type", "")) == "passenger" and str(c.get("requestor_id", "")) == Schema.faction_account(faction) and str(c.get("destination_location", "")) == dest and str(c.get("status", "")) in ["posted", "accepted", "picked_up"]:
            return _reject("n147_passenger_contract_already_outstanding")
    var has_ship: bool = false
    for ship in world.get("ships", {}).values():
        var spec: Dictionary = Catalog.spec(str(ship.get("class", "")))
        if str(ship.get("faction_id", "")) == faction and int(spec.get("passenger_capacity", 0)) >= quantity and str(ship.get("active_contract_id", "")).is_empty() and (ship.get("transit", {}) as Dictionary).is_empty() and float(ship.get("fuel", 0.0)) > 0.0:
            has_ship = true
            break
    if not has_ship:
        return _reject("n147_missing_actual_passenger_hull")
    var money: int = int(world.get("faction_treasuries", {}).get(faction, -1))
    if money - Planner.FACTION_SUBSIDY_FLOOR < price:
        return _reject("n147_faction_subsidy_floor")
    var opened: Dictionary = _open(world, bank)
    if not opened.get("ok", false):
        return opened
    var ledger: Variant = opened["ledger"]
    var board: Variant = opened["board"]
    var cid: String = "n147/passenger/" + faction + "/" + dest + "/" + str(tick)
    var escrow: String = "escrow:" + cid
    if not ledger.register_empty_account(escrow):
        return _reject("n147_duplicate_escrow_account")
    var payer: String = Schema.faction_account(faction)
    var result: Dictionary = board.post(cid, "passenger", payer, escrow,
        "food", quantity, source, dest, price, tick, tick + 800 * mult, "faction")
    if not result.get("ok", false):
        return result
    var staged: Dictionary = world.duplicate(true)
    staged["faction_treasuries"][faction] = ledger.balance(payer)
    staged["escrow_balances"][escrow] = ledger.balance(escrow)
    var contract_snapshot: Dictionary = board.snapshot()
    contract_snapshot["contracts"][cid]["mission_category"] = "strategy.colony.workforce.v1"
    contract_snapshot["contracts"][cid]["faction_id"] = faction
    if not board.restore(contract_snapshot):
        return _reject("n147_contract_metadata_restore_failed")
    var committed: Dictionary = _commit(staged, ledger, board, bank, tick,
        "N147_CANONICAL_PREPAID_PASSENGER_POSTED", cid, "")
    if committed.get("ok", false):
        committed["funded"] = price
    return committed

## The single N104 owner must call this before any physical embark.
## The N84 passenger goal/BT is supplied by the existing N153/N81 source.
static func accept(world: Dictionary, bank: Dictionary,
        cid: String, sid: String, bt: Dictionary, tick: int) -> Dictionary:
    if tick < 1 or not Bt.validate(bt) or not world.get("ships", {}).has(sid):
        return _reject("n104_missing_actual_passenger_plan")
    var c: Dictionary = world.get("contract_board", {}).get("contracts", {}).get(cid, {})
    var ship: Dictionary = world["ships"][sid]
    if str(c.get("contract_type", "")) != "passenger" or str(c.get("status", "")) != "posted" or tick > int(c.get("expires_at_tick", -1)):
        return _reject("n104_passenger_offer_not_posted")
    if str(ship.get("faction_id", "")) != str(c.get("faction_id", "")) or not str(ship.get("active_contract_id", "")).is_empty() or not (ship.get("transit", {}) as Dictionary).is_empty() or not (ship.get("cargo", {}) as Dictionary).is_empty():
        return _reject("n104_ship_not_idle_or_owned")
    if int(Catalog.spec(str(ship.get("class", ""))).get("passenger_capacity", 0)) < int(c.get("quantity", 0)):
        return _reject("n104_insufficient_physical_seats")
    var opened: Dictionary = _open(world, bank)
    if not opened.get("ok", false):
        return opened
    var ledger: Variant = opened["ledger"]
    var board: Variant = opened["board"]
    var comms: float = float(ship.get("comms_bonus", 0.0))
    var result: Dictionary = board.accept(cid, sid, str(ship["faction_id"]), comms, 1.0, tick)
    if not result.get("ok", false):
        return result
    var staged: Dictionary = world.duplicate(true)
    staged["faction_treasuries"][str(c["faction_id"])] = ledger.balance(Schema.faction_account(str(c["faction_id"])))
    staged["escrow_balances"][str(c["escrow_account"])] = ledger.balance(str(c["escrow_account"]))
    staged["ships"][sid]["active_contract_id"] = cid
    staged["ships"][sid]["current_goal"] = "fulfill_passenger_transport"
    staged["ships"][sid]["current_bt"] = bt.duplicate(true)
    staged["ships"][sid]["last_plan_tick"] = tick
    return _commit(staged, ledger, board, bank, tick,
        "N104_PASSENGER_ACCEPTED_AWAITING_PHYSICAL_EMBARK", cid, sid)

## N84 RequestShipTransaction("passenger_embark"/"passenger_delivery").
## No direct travel or undock is performed; N14/N21 must already have
## brought the ship to a real dock at the relevant end of the journey.
static func move(world: Dictionary, bank: Dictionary, cid: String,
        sid: String, operation: String, tick: int) -> Dictionary:
    if tick < 1 or operation not in ["passenger_embark", "passenger_delivery"]:
        return _reject("n104_invalid_physical_passenger_operation")
    if not world.get("ships", {}).has(sid):
        return _reject("n104_passenger_ship_missing")
    var c: Dictionary = world.get("contract_board", {}).get("contracts", {}).get(cid, {})
    var ship: Dictionary = world["ships"][sid]
    var embarking: bool = operation == "passenger_embark"
    var expected: String = "accepted" if embarking else "picked_up"
    var loc: String = str(c.get("source_location", "")) if embarking else str(c.get("destination_location", ""))
    if str(c.get("contract_type", "")) != "passenger" or str(c.get("status", "")) != expected or str(c.get("fulfiller_id", "")) != sid or str(ship.get("active_contract_id", "")) != cid:
        return _reject("n104_not_active_passenger_contract")
    if not _valid_dock(world, ship, loc):
        return _reject("n104_passenger_requires_real_n21_dock")
    var qty: int = int(c.get("quantity", 0))
    if qty < 1 or qty > int(Catalog.spec(str(ship.get("class", ""))).get("passenger_capacity", 0)) or qty > int(Seats.PASSENGER_SEATS.get(str(ship.get("class", "")), 0)):
        return _reject("n104_real_passenger_capacity_mismatch")
    var faction: String = str(c.get("faction_id", ship.get("faction_id", "")))
    var opened: Dictionary = _open(world, bank)
    if not opened.get("ok", false):
        return opened
    var ledger: Variant = opened["ledger"]
    var board: Variant = opened["board"]
    var evidence: Variant = opened["evidence"]
    var staged: Dictionary = world.duplicate(true)
    if not (staged.get("passenger_manifests", {}) is Dictionary and staged.get("passenger_receipts", {}) is Dictionary):
        return _reject("n104_invalid_manifest_registry")
    if not staged.has("passenger_manifests"):
        staged["passenger_manifests"] = {}
    if not staged.has("passenger_receipts"):
        staged["passenger_receipts"] = {}
    var receipt_id: String = "passenger:" + cid + (":embark" if embarking else ":delivery")
    if staged["passenger_receipts"].has(receipt_id):
        return _reject("n104_replayed_physical_passenger_receipt")
    var action: String = "load" if embarking else "unload"
    var wealth_receipt: String = ""
    if embarking:
        if staged["passenger_manifests"].has(cid):
            return _reject("n104_duplicate_embark_manifest")
        var reserve: int = Seats.COLONY_SETTLERS if str(c.get("mission_category", "")) == "strategy.colony.v1" else 0
        var origin: String = _resident(staged, faction, loc, qty + reserve)
        if origin.is_empty():
            return _reject("n104_insufficient_real_settlers")
        var household: Dictionary = staged["populations"][origin]
        var people: int = int(household["count"])
        var wealth: int = int(household["wealth"])
        if people <= 0 or wealth < 0 or wealth > Seats.MAX_SAFE_FLOAT_INT or (
                float(wealth) * float(qty) > float(Seats.MAX_SAFE_FLOAT_INT)):
            return _reject("n104_wealth_requires_exact_i128_adapter")
        var moved: int = int((wealth * qty) / people)
        var pocket: String = "passengers/" + cid
        if not ledger.register_empty_account(pocket):
            return _reject("n104_duplicate_manifest_ledger_account")
        if moved > 0:
            wealth_receipt = "passenger:" + cid + ":wealth_out"
            var paid: Dictionary = ledger.transfer(wealth_receipt,
                Schema.household_account(origin), pocket, moved,
                tick, "real_passenger_wealth_embark")
            if not paid.get("ok", false):
                return paid
        staged["populations"][origin]["count"] = people - qty
        staged["populations"][origin]["wealth"] = ledger.balance(Schema.household_account(origin))
        staged["passenger_manifests"][cid] = {
            "ship_id": sid, "origin_population_id": origin,
            "destination_population_id": "", "faction_id": faction,
            "quantity": qty, "wealth": moved, "initial_wealth": moved,
            "phase": "embarked", "embarked_at_tick": tick}
    else:
        var manifest: Dictionary = staged["passenger_manifests"].get(cid, {})
        if manifest.is_empty() or str(manifest.get("phase", "")) != "embarked" or str(manifest.get("ship_id", "")) != sid or int(manifest.get("quantity", 0)) != qty:
            return _reject("n104_passengers_not_physically_embarked")
        var recipient: String = _resident(staged, faction, loc, 0)
        if recipient.is_empty():
            return _reject("n104_missing_real_destination_household")
        var deposited: int = int(manifest.get("wealth", -1))
        var wallet: String = "passengers/" + cid
        if deposited < 0 or ledger.balance(wallet) != deposited:
            return _reject("n104_passenger_wealth_manifest_diverged")
        if deposited > 0:
            wealth_receipt = "passenger:" + cid + ":wealth_in"
            var returned: Dictionary = ledger.transfer(wealth_receipt,
                wallet, Schema.household_account(recipient), deposited,
                tick, "real_passenger_wealth_arrival")
            if not returned.get("ok", false):
                return returned
        staged["populations"][recipient]["count"] = int(staged["populations"][recipient]["count"]) + qty
        staged["populations"][recipient]["wealth"] = ledger.balance(Schema.household_account(recipient))
        staged["passenger_manifests"][cid]["wealth"] = 0
        staged["passenger_manifests"][cid]["phase"] = "delivered"
        staged["passenger_manifests"][cid]["destination_population_id"] = recipient
    var receipt: Dictionary = {"ok": true, "action": action, "kind": "passenger",
        "ship_id": sid, "contract_id": cid, "operation_id": receipt_id,
        "location_id": loc, "quantity": qty, "tick": tick,
        "wealth_receipt": wealth_receipt}
    staged["passenger_receipts"][receipt_id] = receipt.duplicate(true)
    evidence.receipts[receipt_id] = receipt.duplicate(true)
    var transition: Dictionary = board.confirm_pickup(cid, sid, tick, receipt_id) if embarking else board.confirm_delivery(cid, sid, tick, receipt_id)
    if not transition.get("ok", false):
        return transition
    var credited: int = 0
    if not embarking:
        var settled: Dictionary = board.settle(cid, sid,
            Schema.ship_account(sid), tick)
        if not settled.get("ok", false):
            return settled
        credited = int(settled["paid"])
        staged["ships"][sid]["credits"] = ledger.balance(Schema.ship_account(sid))
        staged["escrow_balances"][str(c["escrow_account"])] = ledger.balance(str(c["escrow_account"]))
        staged["ships"][sid]["active_contract_id"] = ""
        staged["ships"][sid]["current_goal"] = "idle"
        staged["ships"][sid]["current_bt"] = null
        staged["ships"][sid]["current_goal_score"] = 0.0
    var committed: Dictionary = _commit(staged, ledger, board, bank, tick,
        "N104_REAL_PASSENGERS_EMBARKED" if embarking else "N104_REAL_PASSENGERS_DELIVERED_PAID",
        cid, sid)
    if committed.get("ok", false):
        committed["passengers"] = qty
        committed["payout"] = credited
        committed["receipt_id"] = receipt_id
        committed["wealth_receipt_id"] = wealth_receipt
    return committed

## N153 source chooses a real posted Passenger contract; N81/GOAP and
## N84 generate the persistent multi-leg flight plan. This is read-only:
## assigning and escrow top-up still require the single N39 Apply.
static func propose_assignment(world: Dictionary, graph: RefCounted,
        resolver: RefCounted, positions: Dictionary,
        tick: int, scale: float) -> Dictionary:
    if graph == null or resolver == null or tick < 1:
        return _reject("n153_passenger_missing_route_authority")
    var ids: Array = world.get("contract_board", {}).get("contracts", {}).keys()
    ids.sort()
    var ship_ids: Array = world.get("ships", {}).keys()
    ship_ids.sort()
    for cid in ids:
        var c: Dictionary = world["contract_board"]["contracts"][cid]
        if str(c.get("contract_type", "")) != "passenger" or str(c.get("status", "")) != "posted" or tick > int(c.get("expires_at_tick", -1)):
            continue
        var faction: String = str(c.get("faction_id", ""))
        var source: String = str(c.get("source_location", ""))
        var dest: String = str(c.get("destination_location", ""))
        var quantity: int = int(c.get("quantity", 0))
        if not world.get("markets", {}).has(source) or not world.get("markets", {}).has(dest):
            continue
        for sid in ship_ids:
            var ship: Dictionary = world["ships"][sid]
            var here: String = str(ship.get("location", ""))
            if str(ship.get("faction_id", "")) != faction or not str(ship.get("active_contract_id", "")).is_empty() or str(ship.get("current_goal", "")) not in ["", "idle"] or not (ship.get("transit", {}) as Dictionary).is_empty() or not (ship.get("cargo", {}) as Dictionary).is_empty():
                continue
            if int(Catalog.spec(str(ship.get("class", ""))).get("passenger_capacity", 0)) < quantity:
                continue
            if not SourceN147._full_fuel(world, graph, positions, ship, source, dest, scale):
                continue
            var systems: Dictionary = {}
            systems[here] = resolver.system_for_location(here)
            systems[source] = resolver.system_for_location(source)
            systems[dest] = resolver.system_for_location(dest)
            if systems.values().has(""):
                continue
            var comms: float = float(ship.get("comms_bonus", 0.0))
            if not is_finite(comms) or comms < 0.0 or comms > 0.10:
                continue
            var quoted: int = int(round(float(c.get("payment", 0)) * (1.0 + comms)))
            var top_up: int = maxi(0, quoted - int(c.get("reserved", 0)))
            var balance: int = int(world.get("faction_treasuries", {}).get(faction, -1))
            var commerce: Dictionary = {}
            commerce[faction] = true
            var controllers: Dictionary = {}
            controllers[source] = faction
            controllers[dest] = faction
            var quotes: Dictionary = {}
            quotes[str(cid)] = {"valid": balance >= top_up and balance >= 0,
                "top_up": top_up, "quoted_payment": quoted,
                "payer_balance": balance, "reserved": int(c.get("reserved", 0))}
            var choice: Dictionary = NativeN153.select_contract({
                "offers": [{"id": str(cid), "status": "Posted",
                    "contract_type": "Passenger", "faction_id": faction,
                    "requestor_id": faction, "quantity": quantity,
                    "commodity": "food", "source_location": source,
                    "destination_location": dest, "may_accept": true}],
                "ship_id": str(sid), "ship_faction": faction,
                "ship_location": here, "cargo_capacity": int(ship.get("cargo_capacity", 0)),
                "credits": int(ship.get("credits", 0)), "sensor_range_au": float(ship.get("sensor_range_au", 1.0)),
                "system_by_location": systems,
                "commerce_allowed": commerce,
                "controllers": controllers,
                "quotes": quotes,
                "memory": {"price_knowledge": {}}, "tick": tick})
            if str(choice.get("id", "")) != str(cid):
                continue
            var to_source: Dictionary = ShipPlanning._route_legs(graph, here, source)
            var to_dest: Dictionary = ShipPlanning._route_legs(graph, source, dest)
            if to_source.is_empty() or to_dest.is_empty():
                continue
            var routes: Dictionary = {}
            routes[here + "|" + source] = to_source["legs"]
            routes[source + "|" + dest] = to_dest["legs"]
            var tank: float = float(ship.get("fuel_capacity", 0.0))
            if tank <= 0.0:
                continue
            var fuel_bucket: int = Goap.fuel_fraction_to_bucket(float(ship.get("fuel", 0.0)) / tank)
            var req: Dictionary = Plans.plan_request("passenger", {
                "current": here, "source": source, "destination": dest,
                "commodity": "food", "quantity": quantity,
                "contract_id": str(cid), "fuel_bucket": fuel_bucket}, routes)
            if req.is_empty():
                continue
            var initial: Dictionary = Goap.initial("Source" if here == source else "Origin", fuel_bucket)
            initial["docked"] = not str(ship.get("docked_at", "")).is_empty()
            var goap: Dictionary = Goap.plan(initial, "passenger",
                req["loc_map"], int(req.get("max_depth", 16)),
                int(req.get("goal", {}).get("fuel_bucket_min", 0)))
            if goap.is_empty():
                continue
            var actions: Array = []
            for raw in goap.get("actions", []):
                var action: Dictionary = raw.duplicate(true)
                action["kind"] = str(action.get("type", ""))
                action.erase("type")
                if str(action["kind"]) in ["Refuel", "Refit", "GateJump"] or str(action["kind"]).is_empty():
                    actions.clear()
                    break
                actions.append(action)
            if actions.is_empty():
                continue
            var expanded: Array = Plans.compile_plan_to_bt_actions(
                actions, req["loc_map"], routes, true)
            var nodes: Array = []
            for step in expanded:
                var leaf: Dictionary = Bt.action(step)
                if leaf.is_empty():
                    nodes.clear()
                    break
                nodes.append(leaf)
            if nodes.is_empty():
                continue
            var bt: Dictionary = Bt.sequence(nodes)
            if not Bt.validate(bt):
                continue
            return {"ok": true, "assigned": true, "contract_id": str(cid),
                "ship_id": str(sid), "ai_bt": bt,
                "n153_profit": int(choice.get("profit", 0)),
                "n81_cost": int(goap.get("cost", 0))}
    return {"ok": true, "assigned": false, "status": "NO_FUNDED_REAL_PASSENGER_BID"}
