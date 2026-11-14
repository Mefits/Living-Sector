extends RefCounted
## Deferred one-N158-bridge smoke fixture. NOT RUN before full Rust
## source integration is complete. This tests only N84/N146 intent
## wiring; it does not claim an actual settled Godot flight/trade.
const ExploreFixture = preload("res://tests/p2_n80_native_gate_explore_check.gd")
const MineFixture = preload("res://tests/p2_n80_native_mining_source_check.gd")
const Explore = preload("res://scripts/sim/phase2/unified_n80_ship_exploration_stage.gd")
const Mine = preload("res://scripts/sim/phase2/unified_n80_ship_mining_stage.gd")
const Execution = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")
const N90 = preload("res://scripts/simulation/ai/native_ship_transaction_slot.gd")

static func run_checks() -> Dictionary:
    var scout: Dictionary = ExploreFixture.fixture()
    var route := ExploreFixture.FakeGraph.new()
    var geo: Dictionary = ExploreFixture.real_positions()
    var start: Dictionary = Explore.stage(scout, route,
        ExploreFixture.FakeResolver.new(), 12000, {"ship-a": 1},
        geo, 1.0)
    if not start.get("changed", false):
        return {"ok": false, "reason": "n80_live_source_not_admitted"}
    scout["ships"] = start["ships"]
    var leave: Dictionary = Execution._dispatch({"kind": "Undock"},
        {}, scout, route, geo, "ship-a", 12000, 1.0)
    var leaving: Array = leave.get("commands", [])
    if leaving.size() != 1 or str(leaving[0].get("kind", "")) != "ReleaseDock" or (
            str(leaving[0].get("native_source_goal", "")) != "explore"):
        return {"ok": false, "reason": "n80_missing_source_authenticated_n21_undock"}
    scout["ships"]["ship-a"]["location"] = "alpha-dock"
    scout["ships"]["ship-a"]["docked_at"] = ""
    scout["ships"]["ship-a"]["transit"] = {}
    var arrive: Dictionary = Execution._dispatch({"kind": "Dock"},
        {}, scout, route, geo, "ship-a", 12000, 1.0)
    var landing: Array = arrive.get("commands", [])
    if landing.size() != 1 or str(landing[0].get("kind", "")) != "RequestDock" or (
            str(landing[0].get("native_source_goal", "")) != "explore"):
        return {"ok": false, "reason": "n80_missing_canonical_n21_landing"}
    var miner: Dictionary = MineFixture.fixture()
    var mine_route := MineFixture.FakeGraph.new()
    var mine_pos: Dictionary = MineFixture.real_positions()
    var picked: Dictionary = Mine.stage(miner, mine_route,
        MineFixture.FakeResolver.new(), 500, {"miner-a": 1}, mine_pos, 1.0)
    if not picked.get("changed", false):
        return {"ok": false, "reason": "n103_no_live_fired_miner"}
    miner["ships"] = picked["ships"]
    var unlatch: Dictionary = Execution._dispatch({"kind": "Undock"},
        {}, miner, mine_route, mine_pos, "miner-a", 500, 1.0)
    var miner_undock: Array = unlatch.get("commands", [])
    if miner_undock.size() != 1 or str(miner_undock[0].get(
            "native_source_goal", "")) != "mine":
        return {"ok": false, "reason": "n103_mine_wrong_original_n21_owner"}
    # The original frozen N97 market action may sell only actual
    # mined ice. Stage one already-real physical hold (no free mining)
    # and verify N90 exclusive pending RequestShipTransaction intent.
    miner["ships"]["miner-a"]["cargo"] = {"ice": 5}
    miner["ships"]["miner-a"]["transaction"] = N90.empty()
    miner["ships"]["miner-a"]["faction_reputation"] = {}
    miner["faction_relations"] = {}
    var sell: Dictionary = Execution._dispatch(
        {"kind": "Sell", "commodity": "ice", "quantity": 0},
        {}, miner, mine_route, mine_pos, "miner-a", 501, 1.0)
    var moves: Array = sell.get("commands", [])
    if moves.size() != 1 or str(moves[0].get("kind", "")) != (
            "RequestShipTransaction") or str(moves[0].get(
            "operation", "")) != "free_trade" or (
            not (miner["ships"]["miner-a"].get("transaction") is Dictionary)):
        return {"ok": false, "reason": "n103_missing_one_paid_n90_n97_sale"}
    if str(Execution._dispatch({"kind": "Buy", "commodity": "ice"},
            {}, miner, mine_route, mine_pos, "miner-a", 502, 1.0).get(
            "status", "")) != "failure":
        return {"ok": false, "reason": "n103_miner_reentered_unpaid_buy"}
    if miner["facilities"]["real-depot"]["credits"] != 100000 or (
            miner["ships"]["miner-a"]["cargo"].get("ice", -1) != 5):
        return {"ok": false, "reason": "n103_intent_created_goods_or_money"}
    return {"ok": true, "status": "DEFERRED_FULL_GODOT_RUNTIME_NOT_RUN"}
