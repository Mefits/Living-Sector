extends RefCounted
## E-only bounded costs of actual acceptance callsites, outside paid-tick samples.
## No World references or claims about CPU time. A failed oracle is never timed
## as successful evidence; callers must reject the corresponding checkpoint.
const MAX_MILESTONES: int = 8
const SITES: Array[String] = ["direct_checkpoint", "worker_checkpoint_request",
    "exact_parity_oracle", "size_oracle", "n9_event_oracle"]
const TIME_KIND: String = "elapsed_wall_not_cpu"

static func sample(tick: int, costs: Dictionary, parity: Dictionary,
        size_gate: Dictionary, source_gate: Dictionary) -> Dictionary:
    if tick < 1 or not parity.get("accepted", false) or (
            int(parity.get("tick", -1)) != tick):
        return {"accepted": false, "reason": "unverified_exact_parity"}
    if tick in [100, 300, 600, 900]:
        if not size_gate.get("accepted", false) or not source_gate.get("accepted", false) or (
                int(size_gate.get("tick", -1)) != tick or
                int(source_gate.get("tick", -1)) != tick):
            return {"accepted": false, "reason": "unverified_size_oracle"}
    elif not size_gate.is_empty() or not source_gate.is_empty():
        return {"accepted": false, "reason": "unexpected_size_oracle"}
    if costs.size() != SITES.size():
        return {"accepted": false, "reason": "incomplete_site_coverage"}
    var detached: Dictionary = {}
    for site in SITES:
        if typeof(costs.get(site, null)) != TYPE_INT or int(costs[site]) < 0:
            return {"accepted": false, "reason": "invalid_" + site}
        detached[site] = int(costs[site])
    if tick not in [100, 300, 600, 900] and (
            detached["size_oracle"] != 0 or detached["n9_event_oracle"] != 0):
        return {"accepted": false, "reason": "unexpected_size_cost"}
    return {"accepted": true, "tick": tick, "costs": detached,
        "time_kind": TIME_KIND, "included_in_paid_tick_window": false}

static func summarize(rows: Array, milestones: Array[int]) -> Dictionary:
    if rows.is_empty() or rows.size() > MAX_MILESTONES or (
            rows.size() != milestones.size()):
        return {"accepted": false, "reason": "incomplete_milestones"}
    var totals: Dictionary = {}
    var maxima: Dictionary = {}
    for site in SITES:
        totals[site] = 0
        maxima[site] = 0
    var previous: int = 0
    for i in range(rows.size()):
        if not (rows[i] is Dictionary):
            return {"accepted": false, "reason": "malformed_row"}
        var row: Dictionary = rows[i]
        var tick: int = milestones[i]
        if tick <= previous or row.get("accepted", false) != true or (
                typeof(row.get("tick", null)) != TYPE_INT or row["tick"] != tick or
                row.get("time_kind", "") != TIME_KIND or
                row.get("included_in_paid_tick_window", true) != false):
            return {"accepted": false, "reason": "invalid_milestone"}
        if not (row.get("costs") is Dictionary) or row["costs"].size() != SITES.size():
            return {"accepted": false, "reason": "invalid_costs"}
        for site in SITES:
            var value: Variant = row["costs"].get(site)
            if typeof(value) != TYPE_INT or int(value) < 0:
                return {"accepted": false, "reason": "invalid_" + site}
            if tick not in [100, 300, 600, 900] and (
                    site in ["size_oracle", "n9_event_oracle"]) and value != 0:
                return {"accepted": false, "reason": "unexpected_size_cost"}
            totals[site] += value
            maxima[site] = maxi(int(maxima[site]), value)
        previous = tick
    return {"accepted": true, "milestones": milestones.duplicate(),
        "totals_usec": totals, "maxima_usec": maxima,
        "time_kind": TIME_KIND, "included_in_paid_tick_window": false,
        "performance_claim": false}

static func compare_growth(early: Dictionary, late: Dictionary) -> Dictionary:
    for row in [early, late]:
        if row.get("accepted", false) != true or (
                row.get("time_kind", "") != TIME_KIND or
                row.get("included_in_paid_tick_window", true) != false or
                not (row.get("costs") is Dictionary)):
            return {"accepted": false, "reason": "unverified_observation"}
        for site in SITES:
            if typeof(row["costs"].get(site)) != TYPE_INT or row["costs"][site] < 0:
                return {"accepted": false, "reason": "invalid_" + site}
    if typeof(early.get("tick")) != TYPE_INT or typeof(late.get("tick")) != TYPE_INT or (
            early["tick"] not in [100, 300, 600, 900] or
            late["tick"] not in [100, 300, 600, 900] or
            early["tick"] >= late["tick"]):
        return {"accepted": false, "reason": "invalid_growth_bounds"}
    var deltas: Dictionary = {}
    for site in SITES:
        deltas[site] = int(late["costs"][site]) - int(early["costs"][site])
    return {"accepted": true, "from_tick": early["tick"],
        "to_tick": late["tick"], "deltas_usec": deltas,
        "time_kind": TIME_KIND, "performance_claim": false}
