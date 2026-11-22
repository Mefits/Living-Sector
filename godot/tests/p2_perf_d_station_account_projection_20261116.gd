extends RefCounted
## D: station-account projection oracle for the live N18 administration adapter.
## Account identity must track the current market owner, not a cached prior cycle.
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

static func run() -> Dictionary:
    var owners: Array = ["station-earth", "station-mars", "station-earth", "station-new"]
    var job_counts: Array = [0, 1, 64, 128]
    for cycle in range(owners.size()):
        var owner_id: String = owners[cycle]
        var original: Array = []
        for j in range(job_counts[cycle]):
            original.append(Schema.facility_account(owner_id))
        var original_market_owner: String = Schema.facility_account(owner_id)
        # Proposed fast path: compute once per market, then reuse across jobs.
        var account: String = Schema.facility_account(owner_id)
        var projected: Array = []
        for j in range(job_counts[cycle]):
            projected.append(account)
        if projected != original or account != original_market_owner:
            return {"ok": false, "reason": "station_account_projection_mismatch", "cycle": cycle}
        if cycle > 0 and owner_id != owners[cycle - 1]:
            if account == Schema.facility_account(owners[cycle - 1]):
                return {"ok": false, "reason": "stale_market_owner", "cycle": cycle}
    return {"ok": true, "cycles": owners.size()}
