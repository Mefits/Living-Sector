extends SceneTree
## Source Rust N129: MarketIdentity and FacilityOperations share one wallet.
## No invented balance: N9 must settle every proposed transfer exactly.
const Finance = preload("res://scripts/sim/phase2/unified_native_faction_finance_phase.gd")
const Bank = preload("res://scripts/sim/economy/credit_ledger.gd")

func _world(starving: bool) -> Dictionary:
    return {
        "faction_treasuries": {"civ": 30000},
        "facilities": {"station": {
            "faction": "civ", "type": "station",
            "location": "mars-colony", "credits": 0}},
        "markets": {"mars-colony": {
            "owner": "station", "supply": {"food": 7.0, "water": 13.0}}},
        "populations": {"people": {
            "faction": "civ", "location": "mars-colony",
            "wealth": 0 if starving else 500,
            "food_satisfaction": 0 if starving else 50}}
    }

func _initialize() -> void:
    for starving in [false, true]:
        var original: Dictionary = _world(starving)
        var frozen: Dictionary = original.duplicate(true)
        var expected_station: int = 3000
        var expected_household: int = 4000 if starving else 500
        var expected_treasury: int = 23000 if starving else 27000
        var proposal: Dictionary = Finance.propose(original, 25, 1)
        if not proposal.get("ok", false) or not proposal.get("due", false):
            _fail("source original relief cycle rejected")
            return
        if original != frozen:
            _fail("relief planner mutated live input world")
            return
        if int(proposal["facility_credits"]["station"]) != expected_station or (
                int(proposal["population_wealth"]["people"]) != expected_household or
                int(proposal["faction_treasuries"]["civ"]) != expected_treasury):
            _fail("relief alias lost source FacilityOperations credit: " +
                str(proposal))
            return
        var ledger := Bank.new()
        var initial_accounts: Dictionary = {
            "faction/civ": 30000, "facility/station": 0,
            "population/people": 0 if starving else 500}
        if not ledger.import_accounts(initial_accounts):
            _fail("source N9 accounts unavailable")
            return
        var index: int = 0
        for event in proposal["transfers"]:
            var result: Dictionary = ledger.transfer(
                "n129:25:%04d:%s" % [index, str(event["kind"])],
                str(event["source"]), str(event["destination"]),
                int(event["amount"]), 25, str(event["kind"]))
            if not result.get("ok", false):
                _fail("original N9 rejected paid N129 event " + str(result))
                return
            index += 1
        if index != (2 if starving else 1):
            _fail("incorrect original N129 transfer count")
            return
        if ledger.balance("facility/station") != expected_station or (
                ledger.balance("population/people") != expected_household or
                ledger.balance("faction/civ") != expected_treasury or
                ledger.total() != (30000 if starving else 30500)):
            _fail("N129 source proposal and N9 wallet balances diverged")
            return
    var idle: Dictionary = Finance.propose(_world(false), 26, 1)
    if not idle.get("ok", false) or idle.get("due", true) or (
            not idle.get("transfers", []).is_empty()):
        _fail("N129 invented a relief action outside source cadence")
        return
    print("P2_N129_SHARED_FACILITY_WALLET_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N129_SHARED_FACILITY_WALLET_FAIL: " + reason)
    quit(1)
