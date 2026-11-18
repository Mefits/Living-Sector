extends SceneTree
# N151 paid consumption: touched-row ownership oracle and rejected ticket isolation.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n151_consumption_owned_rows.gd

func _apply(source: Dictionary, tickets: Array, sentiment: Dictionary, windows: Dictionary, deep: bool) -> Dictionary:
    var staged: Dictionary = source.duplicate(true) if deep else source.duplicate(false)
    var owned_p: Dictionary = {}
    var owned_f: Dictionary = {}
    var owned_m: Dictionary = {}
    if not deep:
        for domain in ["populations", "facilities", "markets"]:
            staged[domain] = source[domain].duplicate()
    for ticket in tickets:
        var pid: String = ticket["population"]
        var fid: String = ticket["facility"]
        var mid: String = ticket["market"]
        var amount: int = ticket["amount"]
        var units: int = ticket["units"]
        var pop: Dictionary = staged["populations"][pid]
        var fac: Dictionary = staged["facilities"][fid]
        var market: Dictionary = staged["markets"][mid]
        if amount <= 0 or amount > pop["wealth"] or units <= 0 or units > market["supply"]["food"]:
            return {}
        if not deep:
            if not owned_p.has(pid):
                staged["populations"][pid] = pop.duplicate(true)
                owned_p[pid] = true
            if not owned_f.has(fid):
                staged["facilities"][fid] = fac.duplicate(true)
                owned_f[fid] = true
            if not owned_m.has(mid):
                staged["markets"][mid] = market.duplicate(true)
                owned_m[mid] = true
        staged["populations"][pid]["wealth"] -= amount
        staged["facilities"][fid]["credits"] += amount
        staged["markets"][mid]["supply"]["food"] -= units
    for mid in staged["markets"]:
        var market: Dictionary = staged["markets"][mid]
        if market["consumption_window"] != windows[mid]:
            if not deep and not owned_m.has(mid):
                staged["markets"][mid] = market.duplicate(true)
                owned_m[mid] = true
            staged["markets"][mid]["consumption_window"] = windows[mid].duplicate(true)
    for pid in staged["populations"]:
        var pop: Dictionary = staged["populations"][pid]
        for field in sentiment[pid]:
            if pop[field] != sentiment[pid][field]:
                if not deep and not owned_p.has(pid):
                    staged["populations"][pid] = pop.duplicate(true)
                    owned_p[pid] = true
                    pop = staged["populations"][pid]
                pop[field] = sentiment[pid][field]
    return staged

func _initialize() -> void:
    var source: Dictionary = {
        "populations": {
            "p": {"wealth": 30, "sentiment": 1, "nested": {"history": [1]}},
            "q": {"wealth": 10, "sentiment": 2, "nested": {"history": [2]}},
            "idle": {"wealth": 40, "sentiment": 4, "nested": {"history": [3]}}},
        "facilities": {
            "seller": {"credits": 5, "nested": {"stock": [1]}},
            "idle": {"credits": 7, "nested": {"stock": [2]}}},
        "markets": {
            "m": {"supply": {"food": 8}, "consumption_window": {"food": 0}},
            "idle": {"supply": {"food": 10}, "consumption_window": {"food": 0}}},
        "ships": {"s": {"cargo": {"food": 1}}}
    }
    var frozen: Dictionary = source.duplicate(true)
    var tickets: Array = [
        {"population": "p", "facility": "seller", "market": "m", "amount": 3, "units": 2},
        {"population": "q", "facility": "seller", "market": "m", "amount": 2, "units": 1},
        {"population": "p", "facility": "seller", "market": "m", "amount": 4, "units": 1}]
    var sentiment: Dictionary = {"p": {"sentiment": 3}, "q": {"sentiment": 2}, "idle": {"sentiment": 4}}
    var windows: Dictionary = {"m": {"food": 4}, "idle": {"food": 0}}
    var staged: Dictionary = _apply(source, tickets, sentiment, windows, false)
    var oracle: Dictionary = _apply(source, tickets, sentiment, windows, true)
    assert(staged == oracle, "multi-ticket paid consumption diverged from full deep oracle")
    assert(source == frozen, "paid N151 stage mutated authoritative World")
    assert(staged["populations"]["p"]["wealth"] == 23)
    assert(staged["facilities"]["seller"]["credits"] == 14)
    assert(staged["markets"]["m"]["supply"]["food"] == 4)
    staged["populations"]["p"]["nested"]["history"].append(99)
    staged["facilities"]["seller"]["nested"]["stock"].append(99)
    staged["markets"]["m"]["consumption_window"]["food"] = 99
    assert(source == frozen, "detached paid rows leaked nested mutable aliases")
    # Rejected third ticket after two successful staged purchases must not
    # leak either earlier ledger-equivalent changes or stock mutations.
    var rejected: Array = tickets.duplicate(true)
    rejected[2]["amount"] = 999
    assert(_apply(source, rejected, sentiment, windows, false).is_empty())
    assert(source == frozen, "rejected N151 sequence modified canonical World")
    # A sentiment-only tick must detach just its modified population row.
    var only_sentiment: Dictionary = sentiment.duplicate(true)
    only_sentiment["idle"]["sentiment"] = 9
    var no_tickets: Dictionary = _apply(source, [], only_sentiment, windows, false)
    assert(no_tickets == _apply(source, [], only_sentiment, windows, true))
    assert(source == frozen)
    # Negative oracle: shallow registry + direct nested write is unsafe.
    var unsafe: Dictionary = frozen.duplicate(false)
    unsafe["markets"] = frozen["markets"].duplicate(false)
    unsafe["markets"]["m"]["supply"]["food"] = 0
    assert(frozen["markets"]["m"]["supply"]["food"] == 0)
    assert(source["markets"]["m"]["supply"]["food"] == 8)
    quit(0)
