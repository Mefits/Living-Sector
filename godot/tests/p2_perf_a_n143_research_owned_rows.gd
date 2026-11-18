extends SceneTree
# Astra II-B N143: paid shift owned rows vs the former full-domain oracle.
# This fixture mirrors the production mutation boundary after verified N9
# commit/receipt; it does not replace full N39/Schema/N38 replay tests.

func _paid_stage(world: Dictionary, shifts: Array, full_copy: bool) -> Dictionary:
    var staged: Dictionary = world.duplicate(false)
    for domain in ["research_directors", "research", "research_receipts",
            "research_mandates", "faction_charters", "faction_treasuries",
            "facilities", "populations", "markets"]:
        staged[domain] = world[domain].duplicate(full_copy)
    var owned_markets: Dictionary = {}
    var owned_facilities: Dictionary = {}
    var owned_people: Dictionary = {}
    for shift in shifts:
        var fid: String = str(shift.get("faction", ""))
        var location: String = str(shift.get("location", ""))
        var facility_id: String = str(shift.get("facility", ""))
        var population_id: String = str(shift.get("person", ""))
        var receipt: String = str(shift.get("receipt", ""))
        if not staged["faction_treasuries"].has(fid) or (
                not staged["markets"].has(location)) or (
                not staged["facilities"].has(facility_id)) or (
                not staged["populations"].has(population_id)) or (
                staged["research_receipts"].has(receipt)):
            return {"ok": false, "reason": "invalid_actor_or_receipt"}
        var market: Dictionary = staged["markets"][location]
        var facility: Dictionary = staged["facilities"][facility_id]
        var person: Dictionary = staged["populations"][population_id]
        if str(market.get("owner", "")) != facility_id or (
                str(facility.get("faction", "")) != fid) or (
                str(person.get("faction", "")) != fid) or (
                str(person.get("location", "")) != location):
            return {"ok": false, "reason": "stale_ownership"}
        if float(market["supply"]["electronics"]) < 1.0 or (
                int(staged["faction_treasuries"][fid]) < 11):
            return {"ok": false, "reason": "unfunded"}
        # All validations precede mutation, as in N143's verified receipt.
        if not full_copy:
            if not owned_markets.has(location):
                market = market.duplicate(true)
                staged["markets"][location] = market
                owned_markets[location] = true
            if not owned_facilities.has(facility_id):
                facility = facility.duplicate(true)
                staged["facilities"][facility_id] = facility
                owned_facilities[facility_id] = true
            if not owned_people.has(population_id):
                person = person.duplicate(true)
                staged["populations"][population_id] = person
                owned_people[population_id] = true
        market["supply"]["electronics"] -= 1.0
        staged["faction_treasuries"][fid] -= 11
        facility["credits"] += 1
        person["wealth"] += 10
        staged["research_directors"][fid] = {
            "last_research_tick": int(shift.get("tick", 1)),
            "research": ["tech"], "memory": {"history": [receipt]}}
        staged["research"][fid] = ["tech"]
        staged["research_receipts"][receipt] = {"receipt_id": receipt}
    return {"ok": true, "world": staged}

func _initialize() -> void:
    var world: Dictionary = {
        "research_directors": {"a": {"research": []}},
        "research": {"a": []}, "research_receipts": {},
        "research_mandates": {"a": {"mode": "delegated"}},
        "faction_charters": {"a": {"goals": [1]}},
        "faction_treasuries": {"a": 100},
        "facilities": {
            "lab": {"faction": "a", "credits": 2,
                "reserves": {"ore": [1]}},
            "idle": {"faction": "a", "credits": 9,
                "reserves": {"ore": [8]}}},
        "populations": {
            "worker": {"faction": "a", "location": "lab_market",
                "wealth": 3, "needs": {"food": [2]}},
            "idle": {"faction": "a", "location": "idle_market",
                "wealth": 7, "needs": {"food": [9]}}},
        "markets": {
            "lab_market": {"owner": "lab",
                "supply": {"electronics": 5.0}, "history": [3]},
            "idle_market": {"owner": "idle",
                "supply": {"electronics": 8.0}, "history": [10]}},
        "ships": {"ship": {"cargo": [4]}}}
    var original: Dictionary = world.duplicate(true)
    var shifts: Array = [
        {"faction": "a", "location": "lab_market", "facility": "lab",
            "person": "worker", "receipt": "r1", "tick": 1},
        {"faction": "a", "location": "lab_market", "facility": "lab",
            "person": "worker", "receipt": "r2", "tick": 2}]
    var optimized: Dictionary = _paid_stage(world, shifts, false)
    var oracle: Dictionary = _paid_stage(world, shifts, true)
    assert(optimized.get("ok", false))
    assert(optimized["world"] == oracle["world"])
    assert(world == original)
    assert(optimized["world"]["markets"]["lab_market"]["supply"]["electronics"] == 3.0)
    assert(optimized["world"]["populations"]["worker"]["wealth"] == 23)
    assert(optimized["world"]["faction_treasuries"]["a"] == 78)
    # Late invalid shift must not change authoritative World.
    var bad: Array = shifts.duplicate(true)
    bad.append({"faction": "a", "location": "lab_market",
        "facility": "lab", "person": "worker", "receipt": "r2"})
    assert(not _paid_stage(world, bad, false).get("ok", true))
    assert(world == original)
    var unfunded: Dictionary = world.duplicate(true)
    unfunded["faction_treasuries"]["a"] = 10
    var before_unfunded: Dictionary = unfunded.duplicate(true)
    assert(not _paid_stage(unfunded, shifts, false).get("ok", true))
    assert(unfunded == before_unfunded)
    # Nested mutable alias isolation on changed actors and no-op parity.
    optimized["world"]["markets"]["lab_market"]["history"].append(99)
    optimized["world"]["facilities"]["lab"]["reserves"]["ore"].append(99)
    optimized["world"]["populations"]["worker"]["needs"]["food"].append(99)
    assert(world == original)
    assert(_paid_stage(world, [], false)["world"] == _paid_stage(world, [], true)["world"])
    assert(world == original)
    print("PASS p2_perf_a_n143_research_owned_rows")
    quit()
