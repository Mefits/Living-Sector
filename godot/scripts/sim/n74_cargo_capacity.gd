extends RefCounted
## Frozen Rust: agents/ship/components.rs ShipCargo::used/free (u32 units).
## Read-only admission: caller must commit physical inventory and cargo atomically.
const MAX_U32 := 4294967295

static func inspect(hold: Dictionary, capacity: int, commodity: String, quantity: int) -> Dictionary:
	if capacity < 0 or capacity > MAX_U32 or commodity.is_empty() or quantity <= 0 or quantity > MAX_U32:
		return {"ok": false, "reason": "invalid_request"}
	var used: int = 0
	for key in hold:
		if not key is String or String(key).is_empty() or not hold[key] is int:
			return {"ok": false, "reason": "invalid_hold"}
		var amount: int = hold[key]
		if amount < 0 or amount > MAX_U32 or used > MAX_U32 - amount:
			return {"ok": false, "reason": "invalid_hold"}
		used += amount
	if used > capacity:
		return {"ok": false, "reason": "over_capacity"}
	if quantity > capacity - used:
		return {"ok": false, "reason": "insufficient_capacity", "free": capacity - used}
	var previous: int = int(hold.get(commodity, 0))
	if previous > MAX_U32 - quantity:
		return {"ok": false, "reason": "quantity_overflow"}
	return {"ok": true, "used": used, "free_after": capacity - used - quantity, "commodity": commodity, "quantity": quantity}

static func unload(hold: Dictionary, commodity: String, quantity: int) -> Dictionary:
	if commodity.is_empty() or quantity <= 0 or quantity > MAX_U32:
		return {"ok": false, "reason": "invalid_request"}
	if not hold.get(commodity, 0) is int:
		return {"ok": false, "reason": "invalid_hold"}
	var available: int = int(hold.get(commodity, 0))
	if available < quantity or available > MAX_U32:
		return {"ok": false, "reason": "insufficient_cargo"}
	return {"ok": true, "remaining": available - quantity}
