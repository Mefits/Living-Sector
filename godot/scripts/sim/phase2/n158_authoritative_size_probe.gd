extends RefCounted
## PERF E: inspect an ALREADY DETACHED authoritative N39 checkpoint.
## Never hold World aliases or synthesize missing N9/event counters.
## This probe is deliberately bounded to four paid-tick boundaries.
const CHECKPOINTS: Array[int] = [100, 300, 600, 900]
const RECEIPT_FIELDS: Array[String] = [
    "dock_receipts", "cargo_receipts", "research_receipts",
    "construction_receipts", "passenger_receipts",
    "native_gate_pair_receipts", "native_gate_jump_receipts",
    "native_crew_xp_receipts"
]

static func measure(paid_tick: int, world: Dictionary) -> Dictionary:
    if not CHECKPOINTS.has(paid_tick):
        return {}
    if not (world.get("ships") is Dictionary) or not (
            world.get("facilities") is Dictionary):
        return {"valid": false, "reason": "missing_authoritative_world_domain"}
    var result: Dictionary = {"valid": true, "paid_tick": paid_tick,
        "ships": world["ships"].size(), "facilities": world["facilities"].size(),
        "dock_waiting": 0, "receipt_categories": {}, "missing": []}
    for facility in world["facilities"].values():
        if not (facility is Dictionary):
            return {"valid": false, "reason": "invalid_facility"}
        if facility.has("dock_queue"):
            if not (facility["dock_queue"] is Array):
                return {"valid": false, "reason": "invalid_dock_queue"}
            result["dock_waiting"] += facility["dock_queue"].size()
    for field in RECEIPT_FIELDS:
        if not world.has(field):
            result["missing"].append(field)
            continue
        if not (world[field] is Dictionary):
            return {"valid": false, "reason": "invalid_" + field}
        result["receipt_categories"][field] = world[field].size()
    if world.get("contract_board") is Dictionary and (
            world["contract_board"].get("contracts") is Dictionary):
        result["contracts"] = world["contract_board"]["contracts"].size()
    else:
        result["missing"].append("contract_board.contracts")
    # N9 ledger receipts and Source event queue are not N39 World fields.
    # Never label N39 receipts as the authoritative N9 journal.
    result["missing"].append("n9_ledger_receipts")
    result["missing"].append("source_events")
    return result
