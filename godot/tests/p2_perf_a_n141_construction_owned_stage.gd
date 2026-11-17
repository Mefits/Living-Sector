extends SceneTree
# N141 paid labor + N154 materialization + B3 colony owned-stage oracle.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n141_construction_owned_stage.gd

const OWNED: Array[String] = ["construction_sites", "construction_receipts",
    "construction_contracts", "populations", "faction_treasuries",
    "facilities", "markets"]

func _initialize() -> void:
    var before: Dictionary = {
        "construction_sites": {"site": {"labor": {"completed": 2, "required": 3}}},
        "construction_receipts": {"old": {"kind": "delivery"}},
        "construction_contracts": {"contract": "site"},
        "populations": {"p": {"wealth": 20, "employed_fraction": 0.0}},
        "faction_treasuries": {"f": 100},
        "facilities": {"dock": {"type": "construction_dock", "credits": 0,
            "services": ["docking"]}},
        "markets": {"old": {"supply": {"ore": 1.0}}},
        "ships": {"s": {"cargo": {"ore": 5}}},
        "contract_board": {"contracts": {"contract": {"status": "paid"}}},
        "cargo_receipts": {"load": {"quantities": {"ore": 5}}},
        "construction_next_db_id": -3}
    var frozen: Dictionary = before.duplicate(true)
    var oracle: Dictionary = before.duplicate(true)
    var stage: Dictionary = before.duplicate(false)
    for domain in OWNED:
        stage[domain] = before[domain].duplicate(true)
    for candidate in [oracle, stage]:
        candidate["construction_sites"]["site"]["labor"]["completed"] = 3
        candidate["construction_receipts"]["labor"] = {"kind": "labor"}
        candidate["construction_contracts"].erase("contract")
        candidate["populations"]["p"]["wealth"] = 21
        candidate["faction_treasuries"]["f"] = 99
        candidate["facilities"]["dock"]["type"] = "station"
        candidate["facilities"]["dock"]["services"].append("market")
        candidate["markets"]["new"] = {"supply": {}}
        candidate["construction_next_db_id"] = -4
    assert(stage == oracle, "N141 owned stage differs from deep World oracle")
    assert(before == frozen, "rejected N141 stage modified authoritative World")
    # Negative: shallow domain copy aliases nested site labor.
    var unsafe: Dictionary = frozen.duplicate(false)
    unsafe["construction_sites"] = frozen["construction_sites"].duplicate(false)
    unsafe["construction_sites"]["site"]["labor"]["completed"] = 999
    assert(frozen["construction_sites"]["site"]["labor"]["completed"] == 999,
        "negative alias fixture did not reproduce shared nested mutation")
    assert(stage["construction_sites"]["site"]["labor"]["completed"] == 3)
    # A rejected operation must not change any authoritative receipt/wallet.
    assert(before["construction_receipts"] == {"old": {"kind": "delivery"}})
    assert(before["faction_treasuries"]["f"] == 100)
    quit(0)
