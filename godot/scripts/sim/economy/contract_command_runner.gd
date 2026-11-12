extends RefCounted
## N31 CODE_UNVERIFIED. Deterministic tick-driven dispatcher for N26/N27.
## Rust: sim_core/economy/contracts.rs and sim_server/engine/contract_funding.rs.
## This owns command scheduling, NOT the physical inventory or escrow.
## Warehouse dictionaries must be registered by the authoritative world owner.
const Audit = preload("res://scripts/sim/economy/contract_cargo_audit.gd")
const OPERATIONS = ["pickup", "deliver", "settle"]
var _board: RefCounted
var _coordinator: RefCounted
var _cargo: RefCounted
var _ledger: RefCounted
var _warehouses: Dictionary = {}
var _pending: Dictionary = {}
var _results: Dictionary = {}
var last_tick: int = -1

func _init(board: RefCounted, coordinator: RefCounted, cargo: RefCounted, ledger: RefCounted) -> void:
	_board = board
	_coordinator = coordinator
	_cargo = cargo
	_ledger = ledger

## Register references to existing world-owned stocks, never copy or create stock.
func bind_warehouse(location: String, stock: Dictionary) -> bool:
	if location.is_empty() or _warehouses.has(location):
		return false
	_warehouses[location] = stock
	return true

func submit(command_id: String, contract_id: String, ship_id: String, operation: String, due_tick: int, wallet: String = "") -> bool:
	if command_id.is_empty() or contract_id.is_empty() or ship_id.is_empty() or not OPERATIONS.has(operation):
		return false
	if due_tick <= last_tick or due_tick < 0 or _pending.has(command_id) or _results.has(command_id):
		return false
	if operation == "settle" and wallet.is_empty():
		return false
	_pending[command_id] = {"id": command_id, "contract": contract_id, "ship": ship_id, "operation": operation, "due_tick": due_tick, "wallet": wallet}
	return true

## Exactly one pass per authoritative simulation tick. Never called from _process.
## Commands are sorted by (due_tick, command_id), not insertion order or FPS.
func advance(tick: int) -> Dictionary:
	if tick <= last_tick:
		return {"ok": false, "reason": "non_monotonic_tick"}
	var due: Array = []
	for id in _pending:
		if int(_pending[id]["due_tick"]) <= tick:
			due.append(id)
	due.sort_custom(func(a, b):
		var ta := int(_pending[a]["due_tick"])
		var tb := int(_pending[b]["due_tick"])
		return ta < tb or (ta == tb and str(a) < str(b))
	)
	var executed: Array = []
	for id in due:
		var cmd: Dictionary = _pending[id]
		var outcome: Dictionary = _execute(cmd)
		_results[id] = {"command": cmd.duplicate(true), "result": outcome.duplicate(true), "executed_tick": tick}
		_pending.erase(id)
		executed.append({"id": id, "result": outcome.duplicate(true)})
	last_tick = tick
	return {"ok": true, "executed": executed}

func _execute(cmd: Dictionary) -> Dictionary:
	var audit: Dictionary = Audit.new().inspect(_board, _cargo, _ledger)
	if not audit.get("ok", false):
		return {"ok": false, "reason": "preexisting_integrity_failure", "problems": audit.get("problems", []).duplicate()}
	var c: Dictionary = _board.get_contract(str(cmd["contract"]))
	if c.is_empty() or str(c.get("contract_type", "")) != "delivery":
		return {"ok": false, "reason": "unsupported_or_missing_contract"}
	var operation: String = str(cmd["operation"])
	var location := str(c.get("source_location", "")) if operation == "pickup" else str(c.get("destination_location", ""))
	var result: Dictionary
	if operation == "settle":
		result = _coordinator.settle_verified(str(cmd["contract"]), str(cmd["ship"]), str(cmd["wallet"]), int(cmd["due_tick"]))
	else:
		if not _warehouses.has(location):
			return {"ok": false, "reason": "warehouse_not_bound"}
		if operation == "pickup":
			result = _coordinator.pickup(str(cmd["contract"]), str(cmd["ship"]), _warehouses[location], int(cmd["due_tick"]))
		else:
			result = _coordinator.deliver(str(cmd["contract"]), str(cmd["ship"]), _warehouses[location], int(cmd["due_tick"]))
	var after: Dictionary = Audit.new().inspect(_board, _cargo, _ledger)
	if not after.get("ok", false):
		# A diagnostic failure is never reported as a rollback. Inspect world state.
		return {"ok": false, "reason": "post_operation_integrity_failure", "operation_result": result, "problems": after.get("problems", []).duplicate()}
	return result

func result_for(command_id: String) -> Dictionary:
	return (_results.get(command_id, {}) as Dictionary).duplicate(true)

func snapshot() -> Dictionary:
	return {"version": 1, "last_tick": last_tick, "pending": _pending.duplicate(true), "results": _results.duplicate(true)}

## Restore dispatcher AFTER the authoritative world has restored board, cargo,
## ledger, ships and warehouses. This method does not replay any operation.
func restore(data: Dictionary) -> bool:
	if data.get("version") != 1 or typeof(data.get("last_tick")) != TYPE_INT:
		return false
	if not (data.get("pending") is Dictionary) or not (data.get("results") is Dictionary):
		return false
	var next_tick: int = data["last_tick"]
	if next_tick < -1:
		return false
	var pending: Dictionary = data["pending"]
	var results: Dictionary = data["results"]
	for id in pending:
		if not (id is String) or id.is_empty() or results.has(id) or not (pending[id] is Dictionary):
			return false
		var cmd: Dictionary = pending[id]
		if cmd.get("id") != id or not OPERATIONS.has(cmd.get("operation")) or typeof(cmd.get("due_tick")) != TYPE_INT or int(cmd["due_tick"]) <= next_tick:
			return false
		if str(cmd.get("contract", "")).is_empty() or str(cmd.get("ship", "")).is_empty():
			return false
		if cmd["operation"] == "settle" and str(cmd.get("wallet", "")).is_empty():
			return false
	for id in results:
		if not (id is String) or id.is_empty() or not (results[id] is Dictionary):
			return false
		var record: Dictionary = results[id]
		if not (record.get("command") is Dictionary) or not (record.get("result") is Dictionary) or typeof(record.get("executed_tick")) != TYPE_INT:
			return false
		if (record["command"] as Dictionary).get("id") != id or int(record["executed_tick"]) > next_tick:
			return false
	_pending = pending.duplicate(true)
	_results = results.duplicate(true)
	last_tick = next_tick
	return true
