extends RefCounted
## Rust engine/apply.rs SimCommand::ReleaseContract + ContractBoard::release.
## Detached N104 source update; N39 owns ALL publication, N9 is unchanged.
const Relations = preload("res://scripts/sim/phase1/n150_native_full_faction_relations.gd")

static func stage(world: Dictionary, tick: int, ship_id: String,
        contract_id: String, reason: String) -> Dictionary:
    if tick < 1 or ship_id.is_empty() or contract_id.is_empty() or (
            reason not in ["bt_failure", "issuer_funding_failure"] or
            not (world.get("ships") is Dictionary) or
            not (world.get("contract_board") is Dictionary)):
        return {"ok": false, "reason": "n104_release_invalid_source_command"}
    var ships: Dictionary = world["ships"]
    var original: Dictionary = world["contract_board"].get(
        "contracts", {}).get(contract_id, {})
    var old: Dictionary = ships.get(ship_id, {})
    # Frozen Rust ContractBoard::release only accepts Accepted and
    # exact fulfiller; losing speculative accepts MUST be no-ops.
    if original.is_empty() or str(original.get("status", "")) != "accepted" or (
            str(original.get("fulfiller_id", "")) != ship_id):
        return {"ok": true, "changed": false, "status": "GUARDED_NO_OP"}
    if old.is_empty() or str(old.get("active_contract_id", "")) != contract_id or (
            old.get("current_bt") != null):
        return {"ok": false, "reason": "n104_release_ship_still_executing"}
    var qty: int = int(original.get("quantity", 0))
    var good: String = str(original.get("commodity", ""))
    if qty > 0 and int(old.get("cargo", {}).get(good, 0)) >= qty:
        return {"ok": false, "reason": "n104_release_loaded_unmarked_cargo"}
    var next: Dictionary = world.duplicate(true)
    var board: Dictionary = next["contract_board"]["contracts"][contract_id]
    board["status"] = "posted"
    board["fulfiller_id"] = ""
    board["accepted_at_tick"] = -1
    # Source ContractFunding.agreed_payment is None after release;
    # the existing N104 P2 representation has this top-level field.
    board["agreed_payment"] = -1
    # Never refund or decrease prepaid reserved escrow on a release.
    var ship: Dictionary = next["ships"][ship_id]
    ship["active_contract_id"] = ""
    ship["current_goal"] = "idle"
    ship["current_bt"] = null
    ship["current_goal_score"] = 0.0
    ship["dock_attempt_start_tick"] = null
    ship["planning_source"] = "n104_source_release_for_real_rebid"
    var penalty: int = 0
    var faction: String = str(original.get("faction_id", ""))
    if reason != "issuer_funding_failure" and not faction.is_empty():
        penalty = clampi(10 + int(floor(float(original.get("payment", 0)) / 1000.0)), 1, 25)
        var standing: Dictionary = ship.get("faction_reputation", {})
        standing[faction] = maxi(0, int(standing.get(faction, 0)) - penalty)
        ship["faction_reputation"] = standing
        var from_faction: String = str(ship.get("faction_id", ""))
        if not from_faction.is_empty() and from_faction != faction:
            var rel: Dictionary = Relations.bump_standing(
                next.get("faction_relations", {}), from_faction,
                faction, Relations.BREACH_STANDING_PENALTY, tick)
            if not rel.get("ok", false):
                return {"ok": false, "reason": "n104_invalid_source_breach_relations"}
            next["faction_relations"] = rel["pairs"]
    var event: Dictionary = {"kind": "contract_breached" if penalty > 0 else (
        "contract_released"), "contract_id": contract_id,
        "ship_id": ship_id, "rep_penalty": penalty, "tick": tick,
        "reason": reason}
    return {"ok": true, "changed": true, "world": next,
        "status": "N104_ACCEPTED_RELEASED_TO_POSTED",
        "event": event}
