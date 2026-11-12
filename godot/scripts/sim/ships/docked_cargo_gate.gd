extends RefCounted
## N29: single authoritative docking gate for N15 physical cargo transfers.
## Compatible with N21 DockingRegistry shape; no visual nodes or synthetic stock.
const CargoTransfer = preload("res://scripts/sim/ship_cargo_transfer.gd")
var cargo_transfer: RefCounted = CargoTransfer.new()
var docking: RefCounted
var ship_state: RefCounted
var warehouses: Dictionary = {} # facility_id -> shared inventory Dictionary

func configure(docking_registry: RefCounted, ships: RefCounted) -> bool:
	if docking_registry == null or ships == null:
		return false
	docking = docking_registry
	ship_state = ships
	return true

func register_warehouse(facility_id: String, stock: Dictionary) -> bool:
	if docking == null or facility_id.is_empty() or not docking.facilities.has(facility_id):
		return false
	if warehouses.has(facility_id):
		return false
	warehouses[facility_id] = stock
	return true

func transfer(ship_id: String, facility_id: String, quantities: Dictionary, receipt_id: String, direction: String, tick: int) -> Dictionary:
	if docking == null or ship_state == null:
		return {"ok": false, "reason": "unconfigured"}
	if receipt_id.is_empty() or cargo_transfer.receipts.has(receipt_id):
		return {"ok": false, "reason": "duplicate_or_missing_transaction"}
	if not docking.ships.has(ship_id) or not ship_state.ships.has(ship_id):
		return {"ok": false, "reason": "unknown_ship"}
	if not docking.facilities.has(facility_id) or not warehouses.has(facility_id):
		return {"ok": false, "reason": "unknown_warehouse"}
	var dock_ship: Dictionary = docking.ships[ship_id]
	var facility: Dictionary = docking.facilities[facility_id]
	var actual_location: String = str(facility.get("location", ""))
	if bool(dock_ship.get("in_transit", false)) or str(dock_ship.get("docked_at", "")) != facility_id:
		return {"ok": false, "reason": "ship_not_docked_here"}
	if actual_location.is_empty() or str(dock_ship.get("location", "")) != actual_location:
		return {"ok": false, "reason": "dock_location_mismatch"}
	if not docking.occupants.has(facility_id) or not (docking.occupants[facility_id] as Array).has(ship_id):
		return {"ok": false, "reason": "dock_occupancy_mismatch"}
	var cargo_ship: Dictionary = ship_state.ships[ship_id]
	if str(cargo_ship.get("location", "")) != actual_location or not (cargo_ship.get("transit", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "cargo_state_mismatch"}
	return cargo_transfer.move(ship_state, ship_id, warehouses[facility_id], quantities, receipt_id, direction, actual_location, tick)

func snapshot() -> Dictionary:
	return {"version": 1, "cargo_receipts": cargo_transfer.snapshot()}

func restore(data: Dictionary) -> bool:
	if int(data.get("version", -1)) != 1 or not (data.get("cargo_receipts") is Array):
		return false
	return cargo_transfer.restore(data["cargo_receipts"])
