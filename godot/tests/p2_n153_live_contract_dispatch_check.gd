extends SceneTree
## N153 selection -> N104 true accept -> canonical N39 ship obligation.
## Controlled *test-only* price/consumption fixture atop the original
## 24 ships and original real N4 graph; does not inject a fictitious ship,
## market, route, contract Board, Ledger or physically moved commodity.
## Run: godot --headless --path godot --script res://tests/p2_n153_live_contract_dispatch_check.gd
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Demand = preload("res://scripts/sim/phase2/unified_station_demand_phase.gd")
const Selector = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")
const Roster = preload("res://scripts/sim/ships/native_ship_roster.gd")
const Resolver = preload("res://scripts/sim/ships/native_location_resolver.gd")
const SaveState = preload("res://scripts/sim/save_state.gd")

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("frozen source unavailable")
        return
    var a = Runtime.new()
    if not a.start_from_seed(seed):
        _fail("N158 native boot: " + a.boot_error())
        return
    var save: Dictionary = a.checkpoint()
    var w: Dictionary = save["native_production"]["world"]
    if w["ships"].size() != 24:
        _fail("not 24 original ships")
        return
    var buyer: String = str(w["markets"]["alpha-station"]["owner"])
    var seller: String = str(w["markets"]["earth-station"]["owner"])
    # Frozen Rust FactionRelations starts Neutral. Real source faction,
    # market and long-range Huge hauler can accept public delivery offers.
    w["markets"]["alpha-station"]["prices"]["food"] = 60.0
    w["markets"]["earth-station"]["prices"]["food"] = 4.0
    var stock: float = float(w["markets"]["alpha-station"]["supply"]["food"])
    w["markets"]["alpha-station"]["consumption_window"]["food"] = [
        {"tick": 0, "qty": stock + 5.0}]
    var ship_id: String = ""
    var ids: Array = w["ships"].keys()
    ids.sort()
    for sid in ids:
        var ship: Dictionary = w["ships"][sid]
        if ship["class"] == "hauler" and ship["faction_id"] == "terran-authority":
            ship_id = str(sid)
            break
    if ship_id.is_empty():
        _fail("frozen terran Huge hauler missing")
        return
    var roster = Roster.new()
    var resolver = Resolver.new()
    if not roster.load_seed(seed) or not resolver.load_seed(seed):
        _fail("frozen route/position source missing")
        return
    var pos: Dictionary = resolver.positions_from_world(a.world, a.calendar.native_time_units,
        a.calendar.origin_known)
    if not pos.get("ok", false):
        _fail("native world position adapter")
        return
    var policies: Dictionary = {}
    for faction in seed["factions"]:
        policies[str(faction["id"])] = faction
    var no_offer: Dictionary = Selector.propose(w, roster.registry.graph(),
        pos["positions"], resolver, 0, a.clock.tick_scale(), policies)
    if not no_offer.get("ok", false) or not no_offer.get("candidates", []).is_empty():
        _fail("N153 created an autonomous assignment without a posted offer")
        return
    var prior_ship: Dictionary = w["ships"][ship_id].duplicate(true)
    if not a.restore_checkpoint(save, seed):
        _fail("controlled native fixture rejected by N39")
        return
    var needs: Dictionary = Demand.propose(a.economy_snapshot(), 0)
    if not needs.get("ok", false):
        _fail("N135 demand fixture invalid")
        return
    var matched: Dictionary = {}
    for row in needs.get("proposals", []):
        if str(row.get("location", "")) == "alpha-station" and str(row.get("source_location", "")) == "earth-station" and str(row.get("commodity", "")) == "food":
            matched = row
            break
    if matched.is_empty():
        _fail("original N135 did not find actual directed seller")
        return
    var paid: Dictionary = a.production.post_funded_contract(0, matched)
    if not paid.get("ok", false):
        _fail("N39 N104 paid post failed: " + str(paid))
        return
    var receipt: String = "contract:" + str(paid["contract_id"]) + ":post"
    var old_bank: Dictionary = a.checkpoint()["native_production"]["ledger"].duplicate(true)
    if not old_bank["receipts"].has(receipt):
        _fail("N104 source-funded receipt absent")
        return
    a.queue_control("step", 1)
    a.advance_frame(0.0)
    if a.tick_count != 1 or not a.last_phase_failure().is_empty():
        _fail("N153 actual faction tick failed: " + str(a.last_phase_failure()))
        return
    var candidates: Dictionary = a.last_n153_result()
    var after: Dictionary = a.checkpoint()
    var board: Dictionary = after["native_production"]["world"]["contract_board"]["contracts"]
    var id: String = str(paid["contract_id"])
    if not board.has(id):
        _fail("N104 order missing after tick")
        return
    if str(board[id]["status"]) != "accepted" or str(board[id]["fulfiller_id"]) != ship_id:
        _fail("source N153 did not accept original funded N104 offer: " + str(candidates))
        return
    if str(after["native_production"]["world"]["ships"][ship_id].get("active_contract_id", "")) != id:
        _fail("canonical ship obligation not saved")
        return
    var money_after: Dictionary = after["native_production"]["ledger"]
    var expected_topup: int = int(candidates.get("accepted", [{}])[0].get("top_up", -1))
    if expected_topup <= 0 or money_after["balances"]["escrow:" + id] != old_bank["balances"]["escrow:" + id] + expected_topup:
        _fail("N153 did not fund source comms_t2 bonus")
        return
    if not money_after["receipts"].has("contract:" + id + ":topup"):
        _fail("N104 real acceptance top-up receipt not persisted")
        return
    if not money_after["receipts"].has(receipt):
        _fail("N104 payment receipt lost after accept")
        return
    if after["native_production"]["world"]["ships"][ship_id]["cargo"] != prior_ship["cargo"]:
        _fail("accepted contract magically loaded goods")
        return
    var second: Dictionary = a.production.accept_autonomous_delivery(1, {
        "contract_id": id, "ship_id": ship_id, "source_purchase_cost": 20})
    if second.get("ok", false) or a.checkpoint() != after:
        _fail("replayed acceptance mutated contract or money")
        return
    var path: String = "user://tests/p2-n153-live-" + str(Time.get_ticks_usec()) + ".json"
    if SaveState.save_runner(a, path) != OK:
        _fail("N153 save-to-disk failed")
        return
    var b = Runtime.new()
    if not b.start_from_seed(seed) or not SaveState.load_runner(b, seed, path).get("ok", false):
        _fail("N153 file reload did not restore assigned Board and ship")
        return
    if b.funded_contracts_snapshot()["contracts"][id] != board[id]:
        _fail("N153 acceptance changed on file restore")
        return
    if str(b.fleet_snapshot()[ship_id].get("active_contract_id", "")) != id:
        _fail("assigned ship missing after N38 restore")
        return
    b.queue_control("step", 1)
    b.advance_frame(0.0)
    if b.tick_count != 2 or not b.last_phase_failure().is_empty():
        _fail("N153 post-load ship phase did not continue")
        return
    if b.funded_contracts_snapshot()["contracts"][id]["status"] != "accepted":
        _fail("N153 contract illegally auto-completed without a N97 receipt")
        return
    if not b.fleet_snapshot()[ship_id]["cargo"].is_empty():
        _fail("N153 source arrival produced phantom cargo")
        return
    var absolute: String = ProjectSettings.globalize_path(path)
    DirAccess.remove_absolute(absolute)
    DirAccess.remove_absolute(absolute + ".bak")
    print("P2_N153_N104_CANONICAL_ACCEPT_NO_FAKE_CARGO_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N153_ACCEPT_FAIL: " + reason)
    quit(1)
