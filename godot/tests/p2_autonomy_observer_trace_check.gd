extends SceneTree
## Read-only P2 observer proof projection. Run locally with Godot 4.7.2:
## godot --headless --path godot --script res://tests/p2_autonomy_observer_trace_check.gd
const ObserverPanel = preload("res://scripts/observer_panel.gd")

func _initialize() -> void:
    var panel = ObserverPanel.new()
    get_root().add_child(panel)
    var economy: Dictionary = {
        "facilities": {}, "markets": {}, "populations": {},
        "escrow_balances": {"escrow:contract-a": 120},
        "cargo_receipts": {
            "contract:contract-a:load": {"action": "load", "ship_id": "ship-a"},
            "contract:contract-a:unload": {"action": "unload", "ship_id": "ship-a"}
        },
        "contract_board": {"contracts": {
            "contract-a": {
                "status": "paid", "commodity": "food", "quantity": 2,
                "source_location": "earth-station", "destination_location": "alpha-station",
                "fulfiller_id": "ship-a", "escrow_account": "escrow:contract-a"
            },
            "contract-b": {
                "status": "accepted", "commodity": "water", "quantity": 2,
                "source_location": "earth-station", "destination_location": "alpha-station",
                "fulfiller_id": "ship-b", "escrow_account": "escrow:contract-b"
            }
        }}
    }
    var summary: Dictionary = {
        "market_phase_ok": true, "n84_trace": [],
        "last_wages_paid": 0, "last_mining_facilities": 0, "last_recipe_facilities": 0,
        "population_purchases": 0, "last_paid_repairs": 0, "last_service_restock": 0,
        "funded_contracts_this_tick": 0, "contract_admissions_blocked": 0,
        "n153_accepted_this_tick": 0, "n153_blocked_this_tick": 0,
        "n153_departures_this_tick": 0
    }
    var ships: Dictionary = {
        "ship-a": {"location": "alpha-station", "cargo": {}, "current_bt": {},
            "transit": {}, "docked_at": "alpha-station"}
    }
    var proof: Dictionary = {"ledger": {"receipts": {
        "contract:contract-a:payout": {"id": "contract:contract-a:payout"}
    }}}
    panel.show_live_economy(42, economy, summary, ships, proof)
    var text_value: String = panel._label.text
    if not text_value.contains("N15/N97 pickup подтверждён") or not text_value.contains("N15 delivery подтверждён") or not text_value.contains("N104/N9 payout подтверждён"):
        _fail("durable receipts were not projected")
        return
    if not text_value.contains("contract-b · accepted · физического/денежного receipt пока нет"):
        _fail("unproven contract was rendered as evidence")
        return
    print("P2_AUTONOMY_OBSERVER_TRACE_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_AUTONOMY_OBSERVER_TRACE_FAIL: " + reason)
    quit(1)
