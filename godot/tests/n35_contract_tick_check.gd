extends SceneTree
## N35 CODE_UNVERIFIED: godot --headless --path godot --script res://tests/n35_contract_tick_check.gd
const Runner = preload("res://scripts/sim/contract_tick_runner.gd")
const Dispatcher = preload("res://scripts/sim/economy/contract_command_runner.gd")
const Board = preload("res://scripts/sim/economy/contract_board.gd")
const Cargo = preload("res://scripts/sim/ship_cargo_transfer.gd")
const Ships = preload("res://scripts/sim/ship_state.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var seed: Dictionary = _load_seed()
	assert(not seed.is_empty())
	var runner := Runner.new()
	assert(runner.start_from_seed(seed))
	var ships := Ships.new()
	assert(ships.add_ship("ship", "freighter", "faction", "system"))
	ships.ships["ship"]["location"] = "mine"
	var cargo := Cargo.new()
	var ledger := Ledger.new()
	assert(ledger.import_accounts({"buyer": 200, "escrow": 0, "driver": 0}))
	var board := Board.new(ledger)
	var settlement = load("res://scripts/sim/economy/physical_contract_settlement.gd").new(board, cargo, ships)
	var dispatcher := Dispatcher.new(board, settlement, cargo, ledger)
	var mine := {"ore": 20.0}
	var market := {"ore": 0.0}
	assert(dispatcher.bind_warehouse("mine", mine))
	assert(dispatcher.bind_warehouse("market", market))
	assert(runner.configure_contracts(dispatcher))
	assert(not runner.configure_contracts(dispatcher))
	assert(board.post("c", "delivery", "buyer", "escrow", "ore", 8, "mine", "market", 50, 0, 100, "facility")["ok"])
	assert(board.accept("c", "ship", "faction", 0.0, 1.0, 1)["ok"])
	assert(runner.submit_contract_command("pickup", "c", "ship", "pickup", 2))
	assert(not runner.submit_contract_command("pickup", "c", "ship", "pickup", 2))
	assert(runner.implemented_phases().has("apply2"))
	runner._advance_one_tick()
	assert(mine["ore"] == 20.0)
	runner._advance_one_tick()
	assert(mine["ore"] == 12.0)
	assert(dispatcher.last_tick == 2)
	assert(runner.submit_contract_command("deliver", "c", "ship", "deliver", 3))
	assert(runner.submit_contract_command("payout", "c", "ship", "settle", 3, "driver"))
	ships.ships["ship"]["location"] = "market"
	runner._advance_one_tick()
	assert(market["ore"] == 8.0)
	assert(ledger.balance("driver") == 50)
	assert(ledger.total() == 200)
	assert(not runner.submit_contract_command("late", "c", "ship", "settle", 3, "driver"))
	var saved := runner.checkpoint()
	assert(saved["contract_commands"]["last_tick"] == 3)
	assert(not runner.restore_checkpoint(saved, seed))
	assert(not runner.restore_with_contracts(saved, seed, Dispatcher.new(board, settlement, cargo, ledger)))
	assert(runner.restore_with_contracts(saved, seed, dispatcher))
	runner._advance_one_tick()
	assert(ledger.balance("driver") == 50)
	assert(dispatcher.last_tick == 4)
	print("N35_CONTRACT_TICK_OK")
	quit(0)

func _load_seed() -> Dictionary:
	# Reuse the exact P1 test seed rather than inventing an alternate galaxy.
	var paths := ["res://data/galaxy_seed.json", "res://data/seed.json"]
	for path in paths:
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				return parsed
	return {}
