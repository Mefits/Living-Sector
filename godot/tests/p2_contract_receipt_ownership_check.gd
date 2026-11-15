extends SceneTree
## N104 receipt exclusivity regression. Run locally with Godot 4.7.2.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Board = preload("res://scripts/sim/economy/contract_board.gd")
const Cargo = preload("res://scripts/sim/ship_cargo_transfer.gd")

func _initialize() -> void:
	var ledger := Ledger.new()
	assert(ledger.import_accounts({"buyer": 200, "escrow_a": 0, "escrow_b": 0, "driver": 0}))
	var board := Board.new(ledger)
	var cargo := Cargo.new()
	board.bind_physical_cargo(cargo)
	for id in ["a", "b"]:
		var escrow: String = "escrow_" + id
		assert(board.post(id, "delivery", "buyer", escrow, "ore", 5, "mine", "market", 30, 0, 100, "facility").get("ok", false))
		assert(board.accept(id, "ship", "faction", 0.0, 1.0, 1).get("ok", false))
	cargo.receipts["load_1"] = {"ok": true, "ship_id": "ship", "location_id": "mine", "direction": "load", "tick": 2, "quantities": {"ore": 5}}
	assert(board.confirm_pickup("a", "ship", 2, "load_1").get("ok", false))
	assert(board.confirm_pickup("b", "ship", 2, "load_1").get("reason") == "physical_receipt_already_claimed")
	var snapshot: Dictionary = board.snapshot()
	var restored := Board.new(ledger)
	assert(restored.restore(snapshot))
	restored.bind_physical_cargo(cargo)
	assert(restored.confirm_pickup("b", "ship", 3, "load_1").get("reason") == "physical_receipt_already_claimed")
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.erase("receipt_claims")
	var old_reader := Board.new(ledger)
	assert(old_reader.restore(legacy))
	old_reader.bind_physical_cargo(cargo)
	assert(old_reader.confirm_pickup("b", "ship", 3, "load_1").get("reason") == "physical_receipt_already_claimed")
	var tampered: Dictionary = snapshot.duplicate(true)
	tampered["receipt_claims"].clear()
	assert(not Board.new(ledger).restore(tampered))
	assert(ledger.total() == 200 and ledger.balance("buyer") == 140)
	print("P2_N104_RECEIPT_OWNERSHIP_OK")
	quit(0)
