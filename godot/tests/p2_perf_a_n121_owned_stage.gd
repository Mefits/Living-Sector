extends SceneTree
# N121 owned write-set and rejected N98 prepare/acknowledge isolation.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n121_owned_stage.gd

const OWNED: Array[String] = [
    "native_execution", "native_planner_records", "contract_board",
    "escrow_balances", "faction_treasuries", "native_htn_contracts"]

func _stage(source: Dictionary) -> Dictionary:
    var staged: Dictionary = source.duplicate(false)
    for domain in OWNED:
        staged[domain] = source[domain].duplicate(true)
    return staged

func _initialize() -> void:
    var source: Dictionary = {
        "native_execution": {"active": {"f": {"ledger": {
            "steps": [{"status": "ready", "receipt": []}]}}},
            "blocked_until": {}},
        "native_planner_records": {"f": {"status": "n121_active",
            "ledger": {"steps": [{"status": "ready"}]}}},
        "contract_board": {"contracts": {"old": {"status": "posted",
            "meta": {"flags": ["original"]}}}, "receipt_claims": {}},
        "escrow_balances": {"escrow:old": 100},
        "faction_treasuries": {"f": 10000},
        "native_htn_contracts": {"old": {"dispatch_key": "old"}},
        "native_htn_next_id": 2,
        "ships": {"ship": {"cargo": {"ore": 8}}},
        "markets": {"planet": {"supply": {"ore": 10}}},
        "facilities": {"factory": {"credits": 20}}}
    var frozen: Dictionary = source.duplicate(true)
    var oracle: Dictionary = source.duplicate(true)
    var staged: Dictionary = _stage(source)
    # The source N98 pending ledger must be detached independently:
    # prepare/acknowledge can mutate it before the final Schema oracle.
    var pending: Dictionary = source["native_execution"]["active"]["f"].duplicate(true)
    pending["ledger"]["steps"][0]["status"] = "prepared"
    pending["ledger"]["steps"][0]["receipt"].append("r")
    assert(source == frozen, "N121 rejected N98 prepare mutated canonical state")
    for world in [oracle, staged]:
        world["native_execution"]["active"]["f"] = pending.duplicate(true)
        world["native_planner_records"]["f"]["status"] = "n121_active"
        world["contract_board"]["contracts"]["new"] = {
            "status": "posted", "meta": {"flags": ["paid"]}}
        world["escrow_balances"]["escrow:new"] = 200
        world["faction_treasuries"]["f"] = 9800
        world["native_htn_contracts"]["new"] = {"dispatch_key": "new"}
        world["native_htn_next_id"] = 3
    assert(staged == oracle, "N121 paid owned stage differs from full oracle")
    assert(source == frozen, "N121 staged paid operation leaked into World")
    staged["contract_board"]["contracts"]["old"]["meta"]["flags"].append("changed")
    staged["native_execution"]["active"]["f"]["ledger"]["steps"][0]["receipt"].append("later")
    assert(source == frozen, "N121 nested mutable alias escaped into World")
    var rejected: Dictionary = _stage(source)
    rejected["native_planner_records"]["f"]["ledger"]["steps"][0]["status"] = "invalid"
    rejected["contract_board"]["contracts"]["old"]["meta"]["flags"].append("rejected")
    assert(source == frozen, "N121 rejected owned stage changed canonical World")
    var unsafe: Dictionary = source.duplicate(false)
    unsafe["native_execution"] = source["native_execution"].duplicate(false)
    unsafe["native_execution"]["active"]["f"]["ledger"]["steps"][0]["status"] = "unsafe"
    assert(source != frozen, "negative shallow nested alias was not reproduced")
    quit(0)
