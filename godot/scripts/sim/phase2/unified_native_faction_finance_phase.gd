extends RefCounted
## Rust faction.rs::run_tax_cycle / run_bailout_cycle and
## agents/faction/relief.rs::tick_relief, in their original order.
## This file is PURE: N39 will independently revalidate and commit all
## transfer legs with its one existing N9 Ledger.
const Taxes = preload("res://scripts/sim/faction_tax_n129.gd")
const Relief = preload("res://scripts/sim/native_faction_relief.gd")

const BAILOUT_FLOOR: int = 500
const BAILOUT_TARGET: int = 2000
const WORKING_CAPITAL_FLOOR: int = 10000
const COLONY_DOCK: String = "construction_dock"

static func propose(world: Dictionary, tick: int, multiplier: int) -> Dictionary:
    if tick < 1 or multiplier < 1:
        return {"ok": false, "reason": "n129_invalid_native_tick"}
    var tax_due: bool = Taxes.due(tick, multiplier)
    var relief_due: bool = Relief.due(tick, multiplier)
    if not tax_due and not relief_due:
        return {"ok": true, "due": false, "tick": tick, "transfers": []}
    for field in ["facilities", "populations", "markets", "faction_treasuries"]:
        if not (world.get(field) is Dictionary):
            return {"ok": false, "reason": "n129_missing_source_" + field}
    var factions: Dictionary = {}
    var faction_ids: Array = world["faction_treasuries"].keys()
    faction_ids.sort()
    for id in faction_ids:
        factions[id] = {"treasury": int(world["faction_treasuries"][id])}
    var facilities: Dictionary = {}
    var facility_ids: Array = world["facilities"].keys()
    facility_ids.sort()
    for id in facility_ids:
        var fac: Dictionary = world["facilities"][id]
        facilities[id] = {"faction_id": str(fac.get("faction", "")),
            "facility_type": str(fac.get("type", "")),
            "location": str(fac.get("location", "")),
            "credits": int(fac.get("credits", -1))}
    var transfers: Array = []
    if tax_due:
        var taxed: Dictionary = Taxes.tax_cycle(facilities, factions)
        if not taxed.get("ok", false):
            return taxed
        facilities = taxed["facilities"]
        factions = taxed["factions"]
        for row in taxed.get("transfers", []):
            transfers.append({
                "kind": "native_faction_tax",
                "source": "facility/" + str(row["from"]),
                "destination": "faction/" + str(row["to"]),
                "amount": int(row["amount"])})
        # Bailouts use the POST-tax treasury and the same original Rust
        # 500/2000 facility floor/target and 10,000 faction reserve.
        var bailed: Dictionary = Taxes.bailout_cycle(facilities, factions,
            BAILOUT_FLOOR, BAILOUT_TARGET, WORKING_CAPITAL_FLOOR, COLONY_DOCK)
        if not bailed.get("ok", false):
            return bailed
        facilities = bailed["facilities"]
        factions = bailed["factions"]
        for row in bailed.get("transfers", []):
            transfers.append({
                "kind": "native_facility_bailout",
                "source": "faction/" + str(row["from"]),
                "destination": "facility/" + str(row["to"]),
                "amount": int(row["amount"])})
    var population_wealth: Dictionary = {}
    var population_ids: Array = world["populations"].keys()
    population_ids.sort()
    # Preserve the complete population balance projection for N39, but
    # Relief.apply only ever requests aid for a live faction with
    # 0 <= wealth < HOUSEHOLD_MINIMUM. Avoid building and deep-copying
    # five-field DTOs for all other households in its growing registry.
    # This roster is capture-local; owner/wealth changes are visible on
    # the next paid call. Canonical ID order is retained for tie breaks.
    var households: Array = []
    for id in population_ids:
        var p: Dictionary = world["populations"][id]
        var wealth: int = int(p.get("wealth", -1))
        population_wealth[id] = wealth
        if not relief_due or wealth < 0 or wealth >= Relief.HOUSEHOLD_MINIMUM:
            continue
        var faction_id: String = str(p.get("faction", ""))
        if not factions.has(faction_id):
            continue
        households.append({"id": str(id),
            "faction_id": faction_id,
            "location": str(p.get("location", "")),
            "wealth": wealth,
            "food_satisfaction": int(p.get("food_satisfaction", 50))})
    if relief_due:
        var market_rows: Array = []
        var locations: Array = world["markets"].keys()
        locations.sort()
        for loc in locations:
            var m: Dictionary = world["markets"][loc]
            var owner: String = str(m.get("owner", ""))
            if not facilities.has(owner):
                return {"ok": false, "reason": "n129_market_without_real_payer"}
            market_rows.append({
                "id": owner,
                "faction_id": str(facilities[owner]["faction_id"]),
                "location": str(loc),
                "credits": int(facilities[owner]["credits"]),
                "food": float(m.get("supply", {}).get("food", 0.0)),
                "water": float(m.get("supply", {}).get("water", 0.0))})
        # Relief only requests help for essential, cash-starved producers
        # at a same-faction market. Build this read-only eligible roster once
        # rather than deep-copying every facility a second time in Relief.apply.
        # Keep facility_ids' canonical order; Relief sorts final requests by
        # (priority, faction, location, id), not by producer array index.
        var market_by_location: Dictionary = {}
        for market_row in market_rows:
            market_by_location[str(market_row["location"])] = market_row
        var producers: Array = []
        for id in facility_ids:
            var fac: Dictionary = facilities[id]
            var credits: int = int(fac["credits"])
            if credits < 0 or credits >= Relief.PRODUCER_MINIMUM:
                continue
            var faction_id: String = str(fac["faction_id"])
            if not factions.has(faction_id):
                continue
            var location: String = str(fac["location"])
            if not market_by_location.has(location):
                continue
            var market_row: Dictionary = market_by_location[location]
            if str(market_row["faction_id"]) != faction_id:
                continue
            var facility_type: String = str(fac["facility_type"])
            var essential: bool = (facility_type == "farm" and float(
                market_row["food"]) < 20.0) or (facility_type == "refinery" and float(
                market_row["water"]) < 20.0)
            if not essential:
                continue
            producers.append({
                "id": str(id), "faction_id": faction_id,
                "location": location, "type": facility_type,
                "credits": credits})
        var help: Dictionary = Relief.apply({
            "factions": factions, "households": households,
            "markets": market_rows, "producers": producers},
            tick, multiplier, WORKING_CAPITAL_FLOOR)
        var helped: Dictionary = help.get("state", {})
        if not (helped.get("factions") is Dictionary) or not (helped.get("households") is Array):
            return {"ok": false, "reason": "n129_invalid_native_relief_result"}
        factions = helped["factions"]
        for h in helped["households"]:
            population_wealth[str(h["id"])] = int(h["wealth"])
        # The source market is not its own account: its Facility owner
        # is the only real N9 payer. Avoid creating market wallets.
        # Rust MarketIdentity and FacilityIdentity point to the SAME
        # FacilityOperations wallet. The source relief adapter holds market
        # and producer views in separate arrays, so copying both arrays'
        # final balances sequentially would overwrite a real market
        # controller relief with the unchanged producer-view balance.
        # Apply each actual source event ONCE to the canonical facility
        # wallet instead; N39 replays the very same events through N9.
        for event in help.get("events", []):
            var id: String = str(event["recipient_id"])
            var recipient_kind: String = str(event["recipient_kind"])
            var amount: int = int(event["amount"])
            if recipient_kind == "facility":
                if not facilities.has(id) or amount <= 0 or int(
                        facilities[id]["credits"]) > 9223372036854775807 - amount:
                    return {"ok": false, "reason": "n129_invalid_shared_facility_wallet"}
                facilities[id]["credits"] = int(facilities[id]["credits"]) + amount
            elif recipient_kind != "household":
                return {"ok": false, "reason": "n129_invalid_relief_recipient_kind"}
            transfers.append({
                "kind": "native_faction_relief",
                "source": "faction/" + str(event["faction_id"]),
                "destination": ("population/" if recipient_kind == "household" else "facility/") + id,
                "amount": int(event["amount"]),
                "recipient_kind": recipient_kind})
    var final_funds: Dictionary = {}
    var final_facilities: Dictionary = {}
    for faction in factions:
        final_funds[faction] = int(factions[faction]["treasury"])
    for id in facilities:
        final_facilities[id] = int(facilities[id]["credits"])
    return {"ok": true, "due": true, "tick": tick,
        "tax_due": tax_due, "relief_due": relief_due,
        "faction_treasuries": final_funds,
        "facility_credits": final_facilities,
        "population_wealth": population_wealth,
        "transfers": transfers,
        "authority": "source_N129_tax_bailout_and_source_relief_one_N9"}
