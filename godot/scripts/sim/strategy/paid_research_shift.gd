extends RefCounted
## N45 CODE_UNVERIFIED. One synchronous, real paid Rust research shift.
## This is opt-in; no live world hookup, and no automatic technology grants.
## Rust: strategy/director.rs::research and strategy/governance.rs.
const Gate = preload("res://scripts/sim/strategy/research_gate.gd")
const Inventory = preload("res://scripts/sim/economy/inventory_store.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
var gate: RefCounted = Gate.new()
var ledger: RefCounted
var receipts: Dictionary = {}
var last_tick_by_faction: Dictionary = {}

func _init(existing_ledger: RefCounted = null) -> void:
    ledger = existing_ledger if existing_ledger != null else Ledger.new()

## station_stock is the actual market stock Dictionary; all account IDs must exist
## in the supplied ledger. No imaginary second treasury or employee account.
## Caller must verify faction ownership, station type, population location and
## workforce occupancy in the authoritative world before invoking this boundary.
func paid_shift(id: String, faction: String, tick: int, target: String,
        completed: Array, mandate: Dictionary, price: float,
        station_stock: Dictionary, faction_account: String,
        station_account: String, population_account: String,
        free_workers: int, crisis: bool, authority_verified: bool) -> Dictionary:
    if id.is_empty() or faction.is_empty() or tick < 0 or receipts.has(id):
        return {"ok":false,"reason":"invalid_or_duplicate_shift"}
    if last_tick_by_faction.has(faction) and tick <= int(last_tick_by_faction[faction]):
        return {"ok":false,"reason":"already_researched"}
    if not authority_verified or crisis:
        return {"ok":false,"reason":"unverified_authority_or_crisis"}
    if free_workers < 10:
        return {"ok":false,"reason":"insufficient_free_workers"}
    if not is_finite(price) or price < 0.0 or price > 10000.0:
        return {"ok":false,"reason":"invalid_electronics_quote"}
    if Inventory.validate(station_stock) != "" or float(station_stock.get("electronics",0.0)) < 1.0:
        return {"ok":false,"reason":"needs_local_electronics"}
    var next: Dictionary = gate.next_technology(target, completed)
    if not bool(next.get("ok",false)) or str(next.get("next","")).is_empty():
        return {"ok":false,"reason":"no_researchable_technology"}
    if mandate.get("mode") != "delegated":
        return {"ok":false,"reason":"mandate_not_delegated"}
    for key in ["budget","floor","spent"]:
        if typeof(mandate.get(key)) != TYPE_INT:
            return {"ok":false,"reason":"invalid_mandate"}
    var budget: int = mandate["budget"]
    var floor_cr: int = mandate["floor"]
    var spent: int = mandate["spent"]
    var reason: String = gate.mandate_valid(target,budget,floor_cr,spent)
    if reason != "":
        return {"ok":false,"reason":reason}
    var cost: int = int(ceil(price)) + 10
    var treasury: int = ledger.balance(faction_account)
    if treasury < 0 or ledger.balance(station_account) < 0 or ledger.balance(population_account) < 0:
        return {"ok":false,"reason":"unknown_account"}
    if faction_account == station_account or faction_account == population_account or station_account == population_account:
        return {"ok":false,"reason":"account_alias"}
    # Rust Director also reserves 10_000 CR independently of mandate floor.
    if treasury < cost or treasury - cost < 10000:
        return {"ok":false,"reason":"research_reserve"}
    reason = gate.spending_gate(budget,floor_cr,spent,cost,treasury)
    if reason != "":
        return {"ok":false,"reason":reason}
    # Preflight all commodity/account invariants before the sole ledger commit.
    var candidate: Dictionary = station_stock.duplicate(true)
    candidate["electronics"] = float(candidate["electronics"]) - 1.0
    if Inventory.validate(candidate) != "":
        return {"ok":false,"reason":"invalid_post_shift_stock"}
    var payment: Dictionary = ledger.commit(id,[
        {"account":faction_account,"delta":-cost},
        {"account":station_account,"delta":cost-10},
        {"account":population_account,"delta":10}
    ],tick,"research_shift")
    if not bool(payment.get("ok",false)):
        return payment
    station_stock["electronics"] = candidate["electronics"]
    mandate["spent"] = spent + cost
    last_tick_by_faction[faction] = tick
    var receipt: Dictionary = {"id":id,"faction":faction,"tick":tick,
        "technology":str(next["next"]),"work":10,"electronics":1.0,
        "cost":cost,"wages":10,"input_payment":cost-10,
        "ledger_receipt":id}
    receipts[id] = receipt.duplicate(true)
    return {"ok":true,"receipt":receipt.duplicate(true)}

func snapshot() -> Dictionary:
    return {"version":1,"receipts":receipts.duplicate(true),
        "last_tick_by_faction":last_tick_by_faction.duplicate(true)}

## Restoring this boundary alone does not restore ledger or commodity stock.
## Caller MUST restore and validate the entire external economy snapshot first.
func restore(data: Dictionary, external_state_restored: bool = false) -> bool:
    if not external_state_restored or data.get("version") != 1:
        return false
    if not (data.get("receipts") is Dictionary) or not (data.get("last_tick_by_faction") is Dictionary):
        return false
    var new_receipts: Dictionary = data["receipts"]
    var new_ticks: Dictionary = data["last_tick_by_faction"]
    for key in new_receipts:
        var receipt = new_receipts[key]
        if not (key is String) or not (receipt is Dictionary) or receipt.get("id") != key:
            return false
        if not ledger.has_receipt(str(receipt.get("ledger_receipt",""))):
            return false
    for faction in new_ticks:
        if not (faction is String) or typeof(new_ticks[faction]) != TYPE_INT or int(new_ticks[faction]) < 0:
            return false
    receipts = new_receipts.duplicate(true)
    last_tick_by_faction = new_ticks.duplicate(true)
    return true
