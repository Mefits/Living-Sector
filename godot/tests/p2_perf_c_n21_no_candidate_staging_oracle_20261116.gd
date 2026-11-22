extends RefCounted
## C oracle: a no-candidate N21 request must not stage/copy World.
const Dock = preload("res://scripts/sim/phase2/unified_n21_dock_queue_stage.gd")

static func run() -> Dictionary:
    var ship: Dictionary = {
        "id": "ship-c", "location": "empty-orbit", "transit": {},
        "docked_at": "", "credits": 1000}
    var world: Dictionary = {
        "ships": {"ship-c": ship}, "facilities": {
            "far-dock": {"location": "other-orbit", "docking_capacity": 2,
                "type": "station", "dock_queue": ["ship-x"]}},
        "dock_receipts": {}, "large_unrelated_history": []}
    for i in range(512):
        world["large_unrelated_history"].append({"index": i, "value": [i, i + 1]})
    var original: Dictionary = world.duplicate(true)
    var ledger: Dictionary = {"sentinel": [{"paid": true}]}
    var result: Dictionary = Dock.request(world, ledger, "ship-c", "empty-orbit", 7)
    if not result.get("ok", false) or result.get("changed", true):
        return {"ok": false, "reason": "no_candidate_result"}
    if result.get("status", "") != "no_real_dock":
        return {"ok": false, "reason": "wrong_status"}
    if result.get("world", {}) != original or world != original:
        return {"ok": false, "reason": "world_mutated"}
    if result.get("ledger_snapshot", {}) != ledger:
        return {"ok": false, "reason": "ledger_changed"}
    # Negative: an eligible dock must not accidentally use the no-stage path.
    world["facilities"]["far-dock"]["location"] = "empty-orbit"
    var eligible: Dictionary = Dock.request(world, ledger, "ship-c", "empty-orbit", 7)
    if not eligible.get("ok", false) or eligible.get("status", "") == "no_real_dock":
        return {"ok": false, "reason": "eligible_dock_skipped"}
    # No paid receipt is allowed for the negative case.
    if not world["dock_receipts"].is_empty():
        return {"ok": false, "reason": "phantom_receipt"}
    return {"ok": true, "cases": 2}
