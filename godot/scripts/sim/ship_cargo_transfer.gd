extends RefCounted
## N15: integer physical cargo movements, separate from payment and contracts.
## Rust: agents/ship/components.rs ShipCargo uses Cargo<Commodity,u32>.
## No commodity is created: both stock ledgers change together on success.
const Catalog = preload("res://scripts/sim/economy/commodity_catalog.gd")
var receipts: Dictionary = {}

func move(ship_state: RefCounted, ship_id: String, warehouse: Dictionary, quantities: Dictionary, transaction_id: String, direction: String, location_id: String, tick: int) -> Dictionary:
	if transaction_id.is_empty() or receipts.has(transaction_id):
		return {"ok": false, "reason": "duplicate_or_missing_transaction"}
	if tick < 0 or not ship_state.ships.has(ship_id):
		return {"ok": false, "reason": "invalid_ship_or_tick"}
	var ship: Dictionary = ship_state.ships[ship_id]
	if location_id.is_empty() or str(ship.get("location", "")) != location_id or not (ship.get("transit", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "ship_not_at_warehouse"}
	if direction != "load" and direction != "unload":
		return {"ok": false, "reason": "invalid_direction"}
	if quantities.is_empty():
		return {"ok": false, "reason": "empty_transfer"}
	var hold: Dictionary = ship["cargo"]
	if is_same(warehouse, hold):
		return {"ok": false, "reason": "same_inventory"}
	if not _valid_stock(warehouse, false) or not _valid_stock(hold, true):
		return {"ok": false, "reason": "invalid_inventory"}
	var before_hold := hold.duplicate(true)
	var before_warehouse := warehouse.duplicate(true)
	var after_hold := before_hold.duplicate(true)
	var after_warehouse := before_warehouse.duplicate(true)
	var total := 0
	for value in after_hold.values():
		total += int(value)
	for commodity in quantities:
		if typeof(commodity) != TYPE_STRING or not Catalog.contains(commodity):
			return {"ok": false, "reason": "invalid_commodity"}
		if typeof(quantities[commodity]) != TYPE_INT or int(quantities[commodity]) <= 0:
			return {"ok": false, "reason": "non_integer_quantity"}
		var count: int = quantities[commodity]
		var held := int(after_hold.get(commodity, 0))
		var stored := int(after_warehouse.get(commodity, 0))
		if direction == "load":
			if float(after_warehouse.get(commodity, 0.0)) < float(count):
				return {"ok": false, "reason": "insufficient_warehouse_stock"}
			after_warehouse[commodity] = float(after_warehouse.get(commodity, 0.0)) - float(count)
			after_hold[commodity] = held + count
			total += count
		else:
			if held < count:
				return {"ok": false, "reason": "insufficient_ship_cargo"}
			after_hold[commodity] = held - count
			after_warehouse[commodity] = float(after_warehouse.get(commodity, 0.0)) + float(count)
			total -= count
		if total > int(ship["cargo_capacity"]) or total < 0:
			return {"ok": false, "reason": "cargo_capacity"}
	if not _valid_stock(after_hold, true) or not _valid_stock(after_warehouse, false):
		return {"ok": false, "reason": "invalid_result"}
	# All validations precede both writes. Only caller-owned in-memory ledgers
	# are mutated. Contract settlement must be a separate validated operation.
	hold.clear()
	hold.merge(after_hold)
	warehouse.clear()
	warehouse.merge(after_warehouse)
	var receipt := {"ok": true, "transaction_id": transaction_id, "ship_id": ship_id,
		"location_id": location_id, "tick": tick, "direction": direction,
		"quantities": quantities.duplicate(true)}
	receipts[transaction_id] = receipt.duplicate(true)
	return receipt

func snapshot() -> Array:
	var ids := receipts.keys()
	ids.sort()
	var result: Array = []
	for id in ids:
		result.append((receipts[id] as Dictionary).duplicate(true))
	return result

func restore(records: Array) -> bool:
	var next := {}
	for record in records:
		if not record is Dictionary or record.get("ok", false) != true:
			return false
		var id := str(record.get("transaction_id", ""))
		if id.is_empty() or next.has(id) or str(record.get("ship_id", "")).is_empty():
			return false
		if str(record.get("direction", "")) not in ["load", "unload"]:
			return false
		next[id] = record.duplicate(true)
	receipts = next
	return true

func _valid_stock(stock: Dictionary, integer_only: bool) -> bool:
	for commodity in stock:
		if typeof(commodity) != TYPE_STRING or not Catalog.contains(commodity):
			return false
		var value: Variant = stock[commodity]
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			return false
		if not is_finite(float(value)) or float(value) < 0.0:
			return false
		if integer_only and (typeof(value) != TYPE_INT or int(value) < 0):
			return false
	return true
