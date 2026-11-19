extends RefCounted
## N129 relief producer filtering oracle: preserve all paid transfers,
## source eligibility, canonical request order and full output projections.
const Phase = preload("res://scripts/sim/phase2/unified_native_faction_finance_phase.gd")
const Taxes = preload("res://scripts/sim/faction_tax_n129.gd")
const Relief = preload("res://scripts/sim/native_faction_relief.gd")

static func run() -> Dictionary:
    var world: Dictionary = {
        "faction_treasuries": {"a": 20000, "b": 12000},
        "facilities": {
            "f1": {"faction": "a", "location": "earth", "type": "farm", "credits": 5000},
            "f2": {"faction": "b", "location": "mars", "type": "mine", "credits": 10},
            "dock": {"faction": "a", "location": "earth", "type": "construction_dock", "credits": 10}},
        "populations": {},
        "markets": {"earth": {"owner": "f1", "supply": {"food": 8.0, "water": 10.0}},
                    "mars": {"owner": "f2", "supply": {"food": 90.0, "water": 90.0}}}}
    for i in range(360):
        var fid: String = "extra_%03d" % i
        world["facilities"][fid] = {"faction": "a" if i % 2 == 0 else "b",
            "location": "earth" if i % 2 == 0 else "mars",
            "type": "farm" if i % 5 == 0 else ("refinery" if i % 5 == 1 else "mine"),
            "credits": 0 if i % 7 == 0 else (19 if i % 7 == 1 else 3000)}
    for i in range(240):
        world["populations"]["p%03d" % i] = {
            "faction": "a" if i % 2 == 0 else "b",
            "location": "earth" if i % 2 == 0 else "mars",
            "wealth": i, "food_satisfaction": 25 if i % 3 == 0 else 80}
    # Tax is always a subset of relief cadence (200*m vs 25*m).
    # Cover both-due, relief-only and no-op cases across multipliers.
    for case in [[200, 1], [225, 1], [400, 2], [201, 1], [200, 2], [200, 8]]:
        var tick: int = case[0]
        var multiplier: int = case[1]
        var input: Dictionary = world.duplicate(true)
        var got: Dictionary = Phase.propose(input, tick, multiplier)
        var expected: Dictionary = _legacy_oracle(world, tick, multiplier)
        if got != expected:
            return {"ok": false, "reason": "n129_oracle_mismatch",
                    "tick": tick, "multiplier": multiplier,
                    "got": got, "expected": expected}
        if input != world:
            return {"ok": false, "reason": "world_mutated"}
    # Positive mutation between cycles: no cached roster may survive.
    world["populations"]["p000"]["wealth"] = 999
    world["populations"].erase("p001")
    world["populations"]["p999"] = {"faction": "b", "location": "mars", "wealth": 5}
    world["facilities"]["extra_000"]["credits"] = 0
    world["facilities"]["extra_000"]["type"] = "farm"
    var changed: Dictionary = Phase.propose(world, 200, 2)
    if changed != _legacy_oracle(world, 200, 2):
        return {"ok": false, "reason": "changed_producer_oracle"}
    if not changed.get("ok", false) or changed.get("population_wealth", {}).get("p000") != 999 or changed.get("population_wealth", {}).has("p001") or changed.get("population_wealth", {}).get("p999") != 5:
        return {"ok": false, "reason": "stale_population_roster"}
    # Negative: missing registry is rejected even when no household relief.
    var bad: Dictionary = world.duplicate(true)
    bad.erase("populations")
    var rejected: Dictionary = Phase.propose(bad, 200, 2)
    if rejected.get("ok", true) or rejected.get("reason", "") != "n129_missing_source_populations":
        return {"ok": false, "reason": "missing_registry_not_rejected"}
    var invalid_market: Dictionary = world.duplicate(true)
    invalid_market["markets"]["earth"]["owner"] = "missing_owner"
    var invalid: Dictionary = Phase.propose(invalid_market, 225, 1)
    if invalid.get("ok", true) or invalid.get("reason", "") != "n129_market_without_real_payer":
        return {"ok": false, "reason": "invalid_market_owner_not_rejected"}
    return {"ok": true, "cases": 6, "population_rows": 240, "producer_rows": 363}

static func _legacy_oracle(world: Dictionary, tick: int, multiplier: int) -> Dictionary:
    # Original full-household projection path, independently assembled.
    var tax_due: bool = Taxes.due(tick, multiplier)
    var relief_due: bool = Relief.due(tick, multiplier)
    if not tax_due and not relief_due:
        return {"ok": true, "due": false, "tick": tick, "transfers": []}
    var factions: Dictionary = {}
    var ids: Array = world["faction_treasuries"].keys()
    ids.sort()
    for id in ids:
        factions[id] = {"treasury": int(world["faction_treasuries"][id])}
    var facilities: Dictionary = {}
    ids = world["facilities"].keys()
    ids.sort()
    for id in ids:
        var f: Dictionary = world["facilities"][id]
        facilities[id] = {"faction_id": str(f.get("faction", "")),
            "facility_type": str(f.get("type", "")), "location": str(f.get("location", "")),
            "credits": int(f.get("credits", -1))}
    var facility_ids: Array = ids.duplicate()
    var transfers: Array = []
    if tax_due:
        var taxed: Dictionary = Taxes.tax_cycle(facilities, factions)
        if not taxed.get("ok", false):
            return taxed
        facilities = taxed["facilities"]
        factions = taxed["factions"]
        for row in taxed.get("transfers", []):
            transfers.append({"kind": "native_faction_tax", "source": "facility/" + str(row["from"]),
                "destination": "faction/" + str(row["to"]), "amount": int(row["amount"])})
        var bailed: Dictionary = Taxes.bailout_cycle(facilities, factions, 500, 2000, 10000, "construction_dock")
        if not bailed.get("ok", false):
            return bailed
        facilities = bailed["facilities"]
        factions = bailed["factions"]
        for row in bailed.get("transfers", []):
            transfers.append({"kind": "native_facility_bailout", "source": "faction/" + str(row["from"]),
                "destination": "facility/" + str(row["to"]), "amount": int(row["amount"])})
    var population_wealth: Dictionary = {}
    var households: Array = []
    ids = world["populations"].keys()
    ids.sort()
    for id in ids:
        var p: Dictionary = world["populations"][id]
        population_wealth[id] = int(p.get("wealth", -1))
        households.append({"id": str(id), "faction_id": str(p.get("faction", "")),
            "location": str(p.get("location", "")), "wealth": int(p.get("wealth", -1)),
            "food_satisfaction": int(p.get("food_satisfaction", 50))})
    if relief_due:
        var markets: Array = []
        ids = world["markets"].keys()
        ids.sort()
        for loc in ids:
            var m: Dictionary = world["markets"][loc]
            var owner: String = str(m.get("owner", ""))
            if not facilities.has(owner):
                return {"ok": false, "reason": "n129_market_without_real_payer"}
            markets.append({"id": owner, "faction_id": str(facilities[owner]["faction_id"]),
                "location": str(loc), "credits": int(facilities[owner]["credits"]),
                "food": float(m.get("supply", {}).get("food", 0.0)),
                "water": float(m.get("supply", {}).get("water", 0.0))})
        var producers: Array = []
        for id in facility_ids:
            var f: Dictionary = facilities[id]
            producers.append({"id": str(id), "faction_id": str(f["faction_id"]),
                "location": str(f["location"]), "type": str(f["facility_type"]),
                "credits": int(f["credits"])})
        var help: Dictionary = Relief.apply({"factions": factions, "households": households,
            "markets": markets, "producers": producers}, tick, multiplier, 10000)
        var state: Dictionary = help.get("state", {})
        if not (state.get("factions") is Dictionary) or not (state.get("households") is Array):
            return {"ok": false, "reason": "n129_invalid_native_relief_result"}
        factions = state["factions"]
        for h in state["households"]:
            population_wealth[str(h["id"])] = int(h["wealth"])
        for event in help.get("events", []):
            var id: String = str(event["recipient_id"])
            var kind: String = str(event["recipient_kind"])
            var amount: int = int(event["amount"])
            if kind == "facility":
                if not facilities.has(id) or amount <= 0 or int(facilities[id]["credits"]) > 9223372036854775807 - amount:
                    return {"ok": false, "reason": "n129_invalid_shared_facility_wallet"}
                facilities[id]["credits"] = int(facilities[id]["credits"]) + amount
            elif kind != "household":
                return {"ok": false, "reason": "n129_invalid_relief_recipient_kind"}
            transfers.append({"kind": "native_faction_relief",
                "source": "faction/" + str(event["faction_id"]),
                "destination": ("population/" if kind == "household" else "facility/") + id,
                "amount": amount, "recipient_kind": kind})
    var final_funds: Dictionary = {}
    var final_facilities: Dictionary = {}
    for id in factions:
        final_funds[id] = int(factions[id]["treasury"])
    for id in facilities:
        final_facilities[id] = int(facilities[id]["credits"])
    return {"ok": true, "due": true, "tick": tick, "tax_due": tax_due,
        "relief_due": relief_due, "faction_treasuries": final_funds,
        "facility_credits": final_facilities, "population_wealth": population_wealth,
        "transfers": transfers,
        "authority": "source_N129_tax_bailout_and_source_relief_one_N9"}
