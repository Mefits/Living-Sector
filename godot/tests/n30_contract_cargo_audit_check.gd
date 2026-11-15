extends SceneTree
## N30 CODE_UNVERIFIED. Run:
## godot --headless --path godot --script res://tests/n30_contract_cargo_audit_check.gd
const Ships = preload("res://scripts/sim/ship_state.gd")
const Cargo = preload("res://scripts/sim/ship_cargo_transfer.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Board = preload("res://scripts/sim/economy/contract_board.gd")
const Settlement = preload("res://scripts/sim/economy/physical_contract_settlement.gd")
const Audit = preload("res://scripts/sim/economy/contract_cargo_audit.gd")

func _initialize() -> void:
	var ships := Ships.new()
	assert(ships.add_ship("ship", "freighter", "faction", "system"))
	ships.ships["ship"]["location"] = "mine"
	var cargo := Cargo.new()
	var ledger := Ledger.new()
	assert(ledger.import_accounts({"buyer": 200, "escrow": 0, "driver": 0}))
	var board := Board.new(ledger)
	var audit := Audit.new()
	var initial := audit.inspect(board, cargo, ledger)
	assert(initial["ok"] and initial["checked"] == 0)
	assert(board.post("c", "delivery", "buyer", "escrow", "ore", 8, "mine", "market", 50, 0, 100, "facility")["ok"])
	assert(audit.inspect(board, cargo, ledger)["ok"])
	assert(board.accept("c", "ship", "faction", 0.0, 1.0, 1)["ok"])
	assert(audit.inspect(board, cargo, ledger)["ok"])
	var coordinator := Settlement.new(board, cargo, ships)
	var source := {"ore": 20.0}
	var destination := {"ore": 0.0}
	assert(coordinator.pickup("c", "ship", source, 2)["ok"])
	assert(audit.inspect(board, cargo, ledger)["ok"])
	ships.ships["ship"]["location"] = "market"
	assert(coordinator.deliver("c", "ship", destination, 3)["ok"])
	assert(audit.inspect(board, cargo, ledger)["ok"])
	assert(coordinator.settle_verified("c", "ship", "driver", 4)["ok"])
	assert(audit.inspect(board, cargo, ledger)["ok"])
	var original: Dictionary = cargo.receipts["contract:c:unload"].duplicate(true)
	cargo.receipts["contract:c:unload"]["quantities"]["ore"] = 9
	assert(not audit.inspect(board, cargo, ledger)["ok"])
	cargo.receipts["contract:c:unload"] = original
	assert(audit.inspect(board, cargo, ledger)["ok"])
	var ledger_snapshot := ledger.snapshot()
	var cargo_snapshot := cargo.snapshot()
	var board_snapshot := board.snapshot()
	var restored_ledger := Ledger.new()
	assert(restored_ledger.restore(ledger_snapshot))
	var restored_cargo := Cargo.new()
	assert(restored_cargo.restore(cargo_snapshot))
	var restored_board := Board.new(restored_ledger)
	assert(restored_board.restore(board_snapshot))
	assert(audit.inspect(restored_board, restored_cargo, restored_ledger)["ok"])
	assert(not coordinator.settle_verified("c", "ship", "driver", 5)["ok"])
	assert(ledger.total() == 200 and source["ore"] + destination["ore"] == 20.0)
	print("N30_CONTRACT_CARGO_AUDIT_OK")
	quit(0)
