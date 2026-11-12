extends RefCounted
## N108: exact frozen Rust sim_server/engine/apply.rs::
## SimCommand::ReleaseContract, ContractBoard::release and
## faction_relations::BREACH_STANDING_PENALTY.
##
## Caller must not simultaneously run N104 release on the same command.
## Phase 2 combines both into one ContractBoard/index+ledger Apply.
const BREACH_STANDING_PENALTY: int = -1
const MIN_STANDING: int = -100
const MAX_STANDING: int = 100

## world = {contracts:{contract_id: {...}},
##          ships:{ship_id:{faction_id,faction_reputation}},
##          relation_standing:{"min_id\u001fmax_id":{standing,last_event_tick,..}}}
##
## A release resets the contract and keeps its reserved escrow. It does
## not clear ship.active_contract_id (source ship BT cleans that itself).
## No change on losing speculative claim (different fulfiller).
static func apply(world: Dictionary, ship_id: String,
        contract_id: String, reason: String, tick: int) -> Dictionary:
    if ship_id.is_empty() or contract_id.is_empty() or tick < 0:
        return _reject("invalid_release_identity")
    if not (world.get("contracts", null) is Dictionary):
        return _reject("missing_contract_board")
    var src: Variant = world["contracts"].get(contract_id, null)
    if not (src is Dictionary) or str(src.get("status", "")) != "accepted":
        return {"ok": true, "released": false, "world": world,
            "events": [], "reason": "not_accepted"}
    var contract: Dictionary = src
    if str(contract.get("fulfiller_id", "")) != ship_id:
        return {"ok": true, "released": false, "world": world,
            "events": [], "reason": "losing_speculative_accept"}
    var payment: Variant = contract.get("payment", null)
    if typeof(payment) != TYPE_INT:
        return _reject("invalid_contract_payment")
    var issuer_value: Variant = contract.get("faction_id", null)
    var issuer: String = "" if issuer_value == null else str(issuer_value)
    var funding: Variant = contract.get("funding", null)
    if funding != null and not (funding is Dictionary):
        return _reject("invalid_contract_funding")
    var fixed: bool = funding is Dictionary             and str(funding.get("source", "")) == "faction"             and ["strategy.logistics.v1", "strategy.construction.v1",
                 "strategy.colony.v1"].has(str(contract.get("mission_category", "")))
    var initial: Variant = contract.get("initial_payment", null)
    if fixed and typeof(initial) != TYPE_INT:
        return _reject("invalid_fixed_project_payment")
    var staged: Dictionary = world.duplicate(true)
    var c: Dictionary = staged["contracts"][contract_id]
    c["status"] = "posted"
    c["fulfiller_id"] = null
    c["accepted_at_tick"] = null
    if fixed:
        c["payment"] = initial
    if funding is Dictionary:
        c["funding"]["agreed_payment"] = null
    var events: Array = []
    if reason != "issuer_funding_failure" and not issuer.is_empty():
        var ships: Variant = staged.get("ships", null)
        if ships is Dictionary and ships.get(ship_id, null) is Dictionary:
            var ship: Dictionary = ships[ship_id]
            var ship_faction: String = str(ship.get("faction_id", ""))
            var reputation: Variant = ship.get("faction_reputation", null)
            if reputation is Dictionary:
                # Rust i64 integer division truncates toward zero, then
                # clamp into [1,25], no negative/overflow minting.
                var penalty: int = clampi(
                    10 + int(float(payment) / 1000.0), 1, 25)
                var old_rep: Variant = reputation.get(issuer, 0)
                if typeof(old_rep) != TYPE_INT or int(old_rep) < 0:
                    return _reject("invalid_reputation")
                reputation[issuer] = maxi(0, int(old_rep) - penalty)
                events.append({
                    "kind": "contract_breached", "contract_id": contract_id,
                    "ship_id": ship_id, "faction_id": issuer,
                    "rep_penalty": penalty, "reason": reason
                })
            if not ship_faction.is_empty() and ship_faction != issuer:
                if not (staged.get("relation_standing", null) is Dictionary):
                    return _reject("missing_relation_standing")
                var pair: Array = [ship_faction, issuer]
                pair.sort()
                var key: String = str(pair[0]) + "\u001f" + str(pair[1])
                var relation: Variant = staged["relation_standing"].get(key, null)
                # Source bump_standing creates new RelationState tick
                # with standing 0 when the pair had no previous record.
                var state: Dictionary = {
                    "standing": 0, "last_event_tick": tick,
                    "since_tick": tick, "treaty": "neutral"
                } if relation == null else relation
                var before: Variant = state.get("standing", null)
                if typeof(before) != TYPE_INT:
                    return _reject("invalid_relation_standing")
                var after: int = clampi(int(before) +
                    BREACH_STANDING_PENALTY, MIN_STANDING, MAX_STANDING)
                state["standing"] = after
                state["last_event_tick"] = tick
                staged["relation_standing"][key] = state
                events.append({
                    "kind": "faction_standing_changed", "a": ship_faction,
                    "b": issuer, "delta": BREACH_STANDING_PENALTY,
                    "new_standing": after, "cause": "breach",
                    "reason": reason
                })
    return {"ok": true, "released": true,
        "world": staged, "events": events}

static func _reject(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason, "events": []}
