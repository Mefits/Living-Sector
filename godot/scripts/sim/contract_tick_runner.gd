extends "res://scripts/sim/tick_runner.gd"
## N35 CODE_UNVERIFIED. Opt-in contract phase, never a per-frame executor.
## The caller owns the real board, cargo, ledger, ships and warehouse references.
## Rust source: sim_server/engine.rs apply1/apply2; N31 dispatcher enforces
## physical receipt and escrow checks. Contract commands execute at apply2.
var contract_commands: RefCounted
var _contracts_enabled: bool = false
var _last_contract_result: Dictionary = {}

func start_from_seed(seed: Dictionary) -> bool:
	if not super.start_from_seed(seed):
		return false
	contract_commands = null
	_contracts_enabled = false
	_last_contract_result = {}
	return true

func configure_contracts(dispatcher: RefCounted) -> bool:
	if not is_started() or tick_count != 0 or _contracts_enabled or dispatcher == null:
		return false
	if not dispatcher.has_method("advance") or not dispatcher.has_method("submit") or not dispatcher.has_method("snapshot"):
		return false
	var state: Variant = dispatcher.snapshot()
	if not (state is Dictionary) or int(state.get("last_tick", -2)) != -1:
		return false
	contract_commands = dispatcher
	_contracts_enabled = true
	return true

func submit_contract_command(command_id: String, contract_id: String, ship_id: String, operation: String, due_tick: int, wallet: String = "") -> bool:
	if not _contracts_enabled or due_tick <= tick_count:
		return false
	return contract_commands.submit(command_id, contract_id, ship_id, operation, due_tick, wallet)

func implemented_phases() -> PackedStringArray:
	if _contracts_enabled:
		return PackedStringArray(["bodies", "apply2"])
	return super.implemented_phases()

func last_contract_result() -> Dictionary:
	return _last_contract_result.duplicate(true)

func _advance_one_tick() -> void:
	# Preserve the N3 calendar, cadence and event queue. Unlike N23,
	# do not bypass native phase order or drop due event notifications.
	tick_count += 1
	var native_delta: float = clock.tick_scale()
	for phase_index in range(NATIVE_PHASE_ORDER.size()):
		var phase: String = NATIVE_PHASE_ORDER[phase_index]
		if phase == "bodies" and cadence.is_due(phase, tick_count):
			world.advance_orbits(native_delta)
		if phase == "apply2" and _contracts_enabled:
			_last_contract_result = contract_commands.advance(tick_count)
			if not _last_contract_result.get("ok", false):
				push_error("N35 contract dispatcher rejected tick " + str(tick_count))
		for event in events.take_due(tick_count, phase_index):
			scheduled_event_due.emit(event)
	calendar.advance_committed_tick(native_delta)
	tick_completed.emit(tick_count)

func checkpoint() -> Dictionary:
	var data: Dictionary = super.checkpoint()
	if data.is_empty():
		return data
	data["contracts_enabled"] = _contracts_enabled
	if _contracts_enabled:
		data["contract_commands"] = contract_commands.snapshot()
		data["scope"] = "P1 orbits/events and opt-in N31 contract commands; external economy snapshot required"
	return data

func restore_checkpoint(snapshot: Dictionary, frozen_seed: Dictionary) -> bool:
	# Never silently restore a dispatcher without its real external world.
	# A caller must restore board/cargo/ledger/ships/warehouses first and
	# provide the matching dispatcher via restore_with_contracts().
	if snapshot.get("contracts_enabled", false) or _contracts_enabled:
		return false
	if snapshot.has("contract_commands"):
		return false
	return super.restore_checkpoint(snapshot, frozen_seed)

func restore_with_contracts(snapshot: Dictionary, frozen_seed: Dictionary, restored_dispatcher: RefCounted) -> bool:
	# Preflight external dispatcher BEFORE mutating the authoritative world.
	# No cargo/escrow is copied or fabricated by this tick adapter.
	if not _contracts_enabled or restored_dispatcher == null or not restored_dispatcher.has_method("snapshot"):
		return false
	if snapshot.get("contracts_enabled") != true or not (snapshot.get("contract_commands") is Dictionary):
		return false
	var state: Dictionary = restored_dispatcher.snapshot()
	if state != snapshot["contract_commands"] or int(state.get("last_tick", -2)) != int(snapshot.get("tick", -3)):
		return false
	# Parent restore emits tick_completed; observers should connect after
	# restore or read checkpoint state, not treat it as an economy mutation.
	if not super.restore_checkpoint(snapshot, frozen_seed):
		return false
	contract_commands = restored_dispatcher
	_last_contract_result = {}
	return true
