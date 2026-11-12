extends RefCounted
## N146: frozen simulation/commands.rs. Data-only, no World Apply.
## Entity references are stable external IDs supplied by the Phase-2 adapter.
## Commands are ordered by insertion; no implicit sorting, execution or grants.

const SCHEMA_VERSION := 1
const FIELDS := {
	"PlaceBuyOrder": ["ship", "market", "order"],
	"PlaceSellOrder": ["ship", "market", "order"],
	"ExecuteTrade": ["buyer", "seller", "commodity", "quantity", "total_cost"],
	"DockShip": ["ship", "facility"],
	"UndockShip": ["ship"],
	"BeginTransit": ["ship", "from", "to", "departure_tick", "arrival_tick"],
	"ArriveAtLocation": ["ship", "location"],
	"RequestDock": ["ship", "facility_location"],
	"ReleaseDock": ["ship", "facility_location"],
	"RequestShipTransaction": ["ship", "request_id"],
	"GrantCrewXp": ["ship", "skill", "amount"],
	"RequestGateJump": ["ship", "src_gate_location", "dest_gate_location"],
	"PostContract": ["contract_id"],
	"AcceptContract": ["ship", "ship_id", "contract_id"],
	"ExpireContract": ["contract_id"],
	"ReleaseContract": ["ship_id", "contract_id", "reason"],
	"TransferCredits": ["from", "to", "amount"],
	"AddSupplyAtShipLocation": ["ship", "commodity", "quantity"],
	"RemoveSupplyAtShipLocation": ["ship", "commodity", "quantity"],
	"AddSupply": ["market", "commodity", "quantity"],
	"RemoveSupply": ["market", "commodity", "quantity"],
	"DecommissionShip": ["ship", "reason"],
	"RequestRefit": ["ship", "slot", "slug"]
}
const LABELS := {
	"PlaceBuyOrder":"place_buy_order", "PlaceSellOrder":"place_sell_order",
	"ExecuteTrade":"execute_trade", "DockShip":"dock_ship",
	"UndockShip":"undock_ship", "BeginTransit":"begin_transit",
	"ArriveAtLocation":"arrive_at_location", "RequestDock":"request_dock",
	"ReleaseDock":"release_dock", "RequestShipTransaction":"ship_transaction",
	"GrantCrewXp":"grant_crew_xp", "RequestGateJump":"request_gate_jump",
	"PostContract":"post_contract", "AcceptContract":"accept_contract",
	"ExpireContract":"expire_contract", "ReleaseContract":"release_contract",
	"TransferCredits":"transfer_credits",
	"AddSupplyAtShipLocation":"add_supply_at_ship_loc",
	"RemoveSupplyAtShipLocation":"remove_supply_at_ship_loc",
	"AddSupply":"add_supply", "RemoveSupply":"remove_supply",
	"DecommissionShip":"decommission_ship", "RequestRefit":"request_refit"
}
const SHIP_ACTORS := [
	"PlaceBuyOrder", "PlaceSellOrder", "DockShip", "UndockShip",
	"BeginTransit", "ArriveAtLocation", "RequestDock", "ReleaseDock",
	"RequestShipTransaction", "GrantCrewXp", "RequestGateJump",
	"AcceptContract", "AddSupplyAtShipLocation", "RemoveSupplyAtShipLocation",
	"DecommissionShip", "RequestRefit"
]

var _commands: Array[Dictionary] = []
var _phase: String = ""
var _tick: int = -1

static func make_command(kind: String, payload: Dictionary) -> Dictionary:
	if not FIELDS.has(kind):
		return {}
	for field in FIELDS[kind]:
		if not payload.has(field) or payload[field] == null:
			return {}
	if kind == "RequestDock" and not payload.has("preferred_facility_type"):
		payload = payload.duplicate(true)
		payload["preferred_facility_type"] = ""
	var result := {"kind":kind}
	for field in payload.keys():
		result[field] = payload[field]
	return result

static func kind_label(command: Dictionary) -> String:
	return str(LABELS.get(str(command.get("kind", "")), "unknown"))

static func actor_ship(command: Dictionary) -> Variant:
	var kind := str(command.get("kind", ""))
	if kind in SHIP_ACTORS:
		return command.get("ship")
	if kind == "ExecuteTrade":
		return command.get("buyer")
	if kind == "TransferCredits":
		# Rust trace treats the payer as its ship actor, even if not a ship.
		return command.get("from")
	return null

static func trace_detail(command: Dictionary) -> String:
	var kind := str(command.get("kind", ""))
	match kind:
		"PlaceBuyOrder", "PlaceSellOrder":
			var order: Dictionary = command.get("order", {})
			return "%s x%s @ %.1f" % [str(order.get("commodity", "")), str(order.get("quantity", 0)), float(order.get("price", 0))]
		"ExecuteTrade":
			return "%s x%s for %s cr" % [str(command.get("commodity", "")), str(command.get("quantity", 0)), str(command.get("total_cost", 0))]
		"BeginTransit":
			return "%s → %s" % [str(command.get("from", "")), str(command.get("to", ""))]
		"ArriveAtLocation":
			return str(command.get("location", ""))
		"RequestDock":
			var loc := str(command.get("facility_location", ""))
			var preferred := str(command.get("preferred_facility_type", ""))
			return loc if preferred.is_empty() else "%s (%s)" % [loc, preferred]
		"ReleaseDock":
			return str(command.get("facility_location", ""))
		"RequestShipTransaction":
			return "request #%s" % str(command.get("request_id", 0))
		"GrantCrewXp":
			return "%s +%s" % [str(command.get("skill", "")), str(command.get("amount", 0))]
		"RequestGateJump":
			return "%s → %s" % [str(command.get("src_gate_location", "")), str(command.get("dest_gate_location", ""))]
		"PostContract", "AcceptContract", "ExpireContract":
			return str(command.get("contract_id", ""))
		"ReleaseContract":
			return "%s (%s)" % [str(command.get("contract_id", "")), str(command.get("reason", ""))]
		"TransferCredits":
			return "%s cr" % str(command.get("amount", 0))
		"AddSupplyAtShipLocation", "RemoveSupplyAtShipLocation", "AddSupply", "RemoveSupply":
			return "%s %.1f" % [str(command.get("commodity", "")), float(command.get("quantity", 0))]
		"DecommissionShip":
			return str(command.get("reason", ""))
		"RequestRefit":
			return "%s=%s" % [str(command.get("slot", "")), str(command.get("slug", ""))]
	return ""

func begin_phase(tick: int, phase: String) -> bool:
	# Cannot silently drop pending commands when changing a phase.
	if not _commands.is_empty() or tick < 0 or phase.is_empty():
		return false
	_tick = tick
	_phase = phase
	return true

func push(command: Dictionary) -> bool:
	if _tick < 0 or _phase.is_empty():
		return false
	if make_command(str(command.get("kind", "")), command).is_empty():
		return false
	_commands.append(command.duplicate(true))
	return true

func append(other: RefCounted) -> bool:
	if other == self or other._tick != _tick or other._phase != _phase:
		return false
	# Rust Vec::append preserves left-to-right order and empties the source.
	for command in other._commands:
		_commands.append(command.duplicate(true))
	other._commands.clear()
	return true

func drain() -> Array[Dictionary]:
	var result: Array[Dictionary] = _commands.duplicate(true)
	_commands.clear()
	return result

func len() -> int:
	return _commands.size()

func is_empty() -> bool:
	return _commands.is_empty()

func clear() -> void:
	_commands.clear()

func peek() -> Array[Dictionary]:
	return _commands.duplicate(true)

func snapshot() -> Dictionary:
	return {"schema_version":SCHEMA_VERSION, "tick":_tick, "phase":_phase,
		"commands":_commands.duplicate(true)}

func restore(data: Dictionary) -> bool:
	if not _commands.is_empty() or int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return false
	var commands: Variant = data.get("commands")
	if not commands is Array or int(data.get("tick", -1)) < 0 or str(data.get("phase", "")).is_empty():
		return false
	var checked: Array[Dictionary] = []
	for command in commands:
		if not command is Dictionary or make_command(str(command.get("kind", "")), command).is_empty():
			return false
		checked.append(command.duplicate(true))
	_tick = int(data["tick"])
	_phase = str(data["phase"])
	_commands = checked
	return true
