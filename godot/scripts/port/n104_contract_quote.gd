extends RefCounted
## N104 frozen Rust economy/contracts.rs: Contract::fixed_strategy_reward,
## acceptance_payment, funding_top_up; faction_relations.rs trade pact
## payment multiplier; strategy/orders.rs may_accept.
## This is a pure source quote, NOT money movement or a second wallet.

const MAX_F64_EXACT: int = 9007199254740991
const PROJECT_TAGS = [
    "strategy.logistics.v1", "strategy.construction.v1",
    "strategy.colony.v1"
]
const FUNDING_SOURCES = ["population", "facility", "faction"]
const STATUSES = ["posted", "accepted", "picked_up", "delivered", "paid", "expired"]
const OPEN_STATUSES = ["posted", "accepted", "picked_up"]
const TREATIES = ["neutral", "trade_pact", "allied", "tense", "hostile", "war"]

## Accept a stable source representation of pair states by key
## "a\u001fb". Frozen Rust FactionRelations::state(a,b) is symmetric.
## Missing state is neutral; contradictory explicit mirrors fail closed.
static func treaty(relations: Dictionary, a: String, b: String) -> Dictionary:
    if a.is_empty() or b.is_empty() or a == b:
        return {"ok": true, "value": "neutral"}
    var forward: String = a + "\u001f" + b
    var reverse: String = b + "\u001f" + a
    var first: Variant = relations.get(forward, null)
    var second: Variant = relations.get(reverse, null)
    if first == null and second == null:
        return {"ok": true, "value": "neutral"}
    var value: Variant = first if first != null else second
    if not (value is String) or not TREATIES.has(value):
        return _bad("invalid_treaty")
    if second != null and (not (second is String)
            or not TREATIES.has(second) or (first != null and first != second)):
        return _bad("conflicting_treaties")
    return {"ok": true, "value": str(value)}

static func treaty_bonus(relations: Dictionary, ship_faction: String,
        issuer_faction: String) -> Dictionary:
    var info: Dictionary = treaty(relations, ship_faction, issuer_faction)
    if not bool(info.get("ok", false)):
        return info
    var multiplier: float = 1.0
    if not ship_faction.is_empty() and not issuer_faction.is_empty()             and ship_faction != issuer_faction:
        match str(info["value"]):
            "trade_pact":
                multiplier = 1.10
            "allied":
                multiplier = 1.15
    return {"ok": true, "value": multiplier}

static func commerce_allowed(relations: Dictionary, a: String, b: String) -> Dictionary:
    var relation: Dictionary = treaty(relations, a, b)
    if not bool(relation.get("ok", false)):
        return relation
    return {"ok": true, "allowed": not ["hostile", "war"].has(str(relation["value"]))}

## Fixed faction-funded strategic reward is POST-TIME initial_payment,
## unmodified by comms and treaty and capped by approved strategy budget.
static func fixed_reward(contract: Dictionary) -> Dictionary:
    var funding: Variant = contract.get("funding", null)
    if funding == null:
        return {"ok": true, "fixed": false}
    if not (funding is Dictionary):
        return _bad("invalid_funding")
    if not FUNDING_SOURCES.has(str(funding.get("source", ""))):
        return _bad("invalid_funding_source")
    var strategy: bool = str(funding["source"]) == "faction"             and PROJECT_TAGS.has(str(contract.get("mission_category", "")))
    if not strategy:
        return {"ok": true, "fixed": false}
    var initial: Variant = contract.get("initial_payment", null)
    if not _money(initial):
        return _bad("invalid_payment")
    return {"ok": true, "fixed": true, "value": int(initial)}

## `comms_bonus` is the saved ShipFitting.derived.comms_bonus or 0.0
## if the optional component does not exist; do not randomize.
static func quote(contract: Dictionary, ship: Dictionary,
        relations: Dictionary) -> Dictionary:
    var fixed: Dictionary = fixed_reward(contract)
    if not bool(fixed.get("ok", false)):
        return fixed
    if bool(fixed["fixed"]):
        return {"ok": true, "payment": int(fixed["value"])}
    var payment: Variant = contract.get("payment", null)
    if typeof(payment) != TYPE_INT:
        return _bad("invalid_payment")
    var bonus: Variant = ship.get("comms_bonus", 0.0)
    if not _number(bonus):
        return _bad("invalid_comms_bonus")
    var contract_faction: String = str(contract.get("faction_id", ""))
    var info: Dictionary = treaty_bonus(relations,
        str(ship.get("faction_id", "")), contract_faction)
    if not bool(info.get("ok", false)):
        return info
    var float_payment: float = round(
        float(payment) * (1.0 + float(bonus)) * float(info["value"]))
    if not is_finite(float_payment) or float_payment < 0.0             or float_payment > float(MAX_F64_EXACT):
        return _bad("invalid_payment")
    return {"ok": true, "payment": int(float_payment)}

## Preserve Rust saturating_sub: no second debit if fully prepaid.
## A fixed-reward strategy order can NEVER require a payer top-up.
static func top_up(contract: Dictionary, payment: int) -> Dictionary:
    var funding: Variant = contract.get("funding", null)
    if not (funding is Dictionary):
        return _bad("unverified_legacy_funding")
    var reserved: Variant = funding.get("reserved", null)
    if not _money(reserved) or payment < 0:
        return _bad("invalid_contract_escrow")
    var extra: int = maxi(payment - int(reserved), 0)
    var fixed: Dictionary = fixed_reward(contract)
    if not bool(fixed.get("ok", false)):
        return fixed
    if extra > 0 and bool(fixed["fixed"]):
        return _bad("invalid_contract_escrow")
    return {"ok": true, "added": extra}

## Rust strategy::orders::may_accept, including special public
## unassigned *facility* request while its order executor is unset.
static func may_accept(contract: Dictionary, ship_id: String,
        ship_faction: String) -> bool:
    var funding: Variant = contract.get("funding", null)
    if not (funding is Dictionary):
        return true  # funding validation is performed by accept() itself.
    var order: Variant = funding.get("station_order", null)
    if order == null:
        return true
    if not (order is Dictionary):
        return false
    var executor: Variant = order.get("executor_id", null)
    if str(funding.get("source", "")) == "facility" and executor == null:
        return true
    return str(contract.get("faction_id", "")) == ship_faction         and executor != null and str(executor) == ship_id

static func _money(value: Variant) -> bool:
    return typeof(value) == TYPE_INT and int(value) >= 0

static func _number(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))

static func _bad(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
