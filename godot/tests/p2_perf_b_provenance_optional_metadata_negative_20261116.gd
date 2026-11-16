extends SceneTree
## Targeted negative regression: provenance must verify optional write-off
## metadata as well as the required payment legs.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	assert(ledger.import_accounts({"ship:s1": 20, "treasury": 5}))
	var removed: Dictionary = ledger.close_removed_entity_account(
		"close-s1", "ship:s1", 7, "ship_decommissioned")
	assert(removed.get("ok", false))
	var actual: Dictionary = ledger.receipt_copy("close-s1")
	assert(ledger.verify_operation_provenance([actual]))
	var forged: Dictionary = actual.duplicate(true)
	forged["credits_lost"] = 21
	assert(not ledger.verify_operation_provenance([forged]))
	forged = actual.duplicate(true)
	forged["account_closed"] = "ship:s2"
	assert(not ledger.verify_operation_provenance([forged]))
	forged = actual.duplicate(true)
	forged["unexpected_claim"] = "fake"
	assert(not ledger.verify_operation_provenance([forged]))
	assert(ledger.verify_operation_provenance([actual]))
	assert(ledger.balance("treasury") == 5)
	assert(ledger.receipt_count() == 1)
	print("PASS p2_perf_b_provenance_optional_metadata_negative_20261116")
	quit()
