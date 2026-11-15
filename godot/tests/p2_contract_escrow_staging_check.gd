extends SceneTree
## Run with Godot --headless --path godot --script res://tests/p2_contract_escrow_staging_check.gd
const Stage = preload("res://scripts/sim/phase2/unified_contract_escrow_staging.gd")
const Demand = preload("res://scripts/sim/phase2/unified_station_demand_phase.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Board = preload("res://scripts/sim/economy/contract_board.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

func _initialize() -> void:
	var world := {
		"facilities": {
			"buyer": {"location": "dest", "credits": 1000, "faction": "a"},
			"seller": {"location": "source", "credits": 1000, "faction": "b"}
		},
		"markets": {
			"dest": {"owner": "buyer", "supply": {"Water": 0.0},
				"prices": {"Water": 10.0},
				"consumption_window": {"Water": [{"tick": 1, "qty": 5.0}]}},
			"source": {"owner": "seller", "supply": {"Water": 20.0},
				"prices": {"Water": 10.0}, "consumption_window": {}}
		}
	}
	var ledger := Ledger.new()
	assert(ledger.import_accounts({
		Schema.facility_account("buyer"): 1000,
		Schema.facility_account("seller"): 1000
	}))
	var board := Board.new(ledger)
	var proposal: Dictionary = Demand.propose(world, 1)
	assert(proposal.get("ok", false) and proposal["proposals"].size() == 1)
	var demand: Dictionary = proposal["proposals"][0]
	var initial_ledger: Dictionary = ledger.snapshot()
	var initial_board: Dictionary = board.snapshot()
	var staged: Dictionary = Stage.stage(world, initial_ledger, initial_board, demand, 1)
	assert(staged.get("ok", false), str(staged))
	assert(staged["status"] == "STAGED_NOT_APPLIED")
	assert(ledger.snapshot() == initial_ledger)
	assert(board.snapshot() == initial_board)
	var escrow: String = str(staged["escrow_account"])
	assert(int(staged["ledger_snapshot"]["balances"][escrow]) == 50)
	assert(int(staged["ledger_snapshot"]["balances"][Schema.facility_account("buyer")]) == 950)
	assert(staged["board_snapshot"]["contracts"].size() == 1)
	var replay: Dictionary = Stage.stage(world, staged["ledger_snapshot"],
			staged["board_snapshot"], demand, 1)
	assert(not replay.get("ok", true))
	var no_funds: Dictionary = initial_ledger.duplicate(true)
	no_funds["balances"][Schema.facility_account("buyer")] = 0
	assert(not Stage.stage(world, no_funds, initial_board, demand, 1).get("ok", true))
	print("P2 escrow staging PASS (candidate only; no canonical Apply)")
	quit(0)
