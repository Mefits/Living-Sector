extends SceneTree
## II-A.2: strict N39/N9 market-only + N21 dock write-set ownership.
## Read/write boundary must reject bad proposals before publishing ANY
## money/world, and never retain external nested arrays/dictionaries.
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")

func _initialize() -> void:
    var sim = Runtime.new()
    if not sim.start_from_seed(Native.load_current_world()):
        _fail("original source native N39/N9 seed rejected")
        return
    if not sim.queue_control("pause") or not sim.queue_control("speed", 8.0):
        _fail("source time controls rejected")
        return
    sim.advance_frame(0.0)
    if not sim.queue_control("step", 1):
        _fail("native tick step rejected")
        return
    sim.advance_frame(0.0)
    if sim.tick_count != 1 or not sim.last_phase_failure().is_empty():
        _fail("original N39 production tick rejected " +
            str(sim.last_phase_failure()))
        return
    var before: Dictionary = sim.production.snapshot()
    var world: Dictionary = before["world"]
    var market_ids: Array = world["markets"].keys()
    market_ids.sort()
    if market_ids.size() != 3:
        _fail("expected three actual native markets")
        return
    var market_id: String = str(market_ids[0])
    var price_keys: Array = world["markets"][market_id]["prices"].keys()
    price_keys.sort()
    if price_keys.is_empty():
        _fail("native source market has no price")
        return
    var commodity: String = str(price_keys[0])
    var updates: Dictionary = {}
    for location in market_ids:
        var m: Dictionary = world["markets"][location]
        updates[location] = {"id": m["id"]}
        for field in ["prices", "demand", "seed_demand",
                "consumption_window", "orders", "history"]:
            if not (m.get(field, null) is Dictionary):
                _fail("original native market missing " + field)
                return
            updates[location][field] = m[field].duplicate(true)

    var invalid: Dictionary = updates.duplicate(true)
    invalid[market_id]["prices"][commodity] = -1.0
    if sim.production.apply_market_phase(1, invalid):
        _fail("negative source market quote accepted")
        return
    if sim.production.snapshot() != before:
        _fail("rejected market change mutated N39/N9")
        return
    invalid = updates.duplicate(true)
    invalid[market_id]["id"] = "market-that-does-not-exist"
    if sim.production.apply_market_phase(1, invalid):
        _fail("forged market identity accepted")
        return
    if sim.production.snapshot() != before:
        _fail("forged identity mutated authoritative World or N9")
        return
    if not sim.production.apply_market_phase(1, updates):
        _fail("source-equivalent market write set rejected")
        return
    if sim.production.snapshot() != before:
        _fail("unchanged market write set altered source economy")
        return
    updates[market_id]["prices"][commodity] = 999999.0
    updates[market_id]["history"].clear()
    if sim.production.snapshot() != before:
        _fail("external market update aliases authoritative World")
        return

    # N21 accepts a canonical unchanged proposal but is never allowed
    # to retain nested World references from its external proposal.
    var dock: Dictionary = {"ok": true, "changed": false,
        "status": "unchanged", "world": world.duplicate(true),
        "ledger_snapshot": before["ledger"].duplicate(true)}
    var accepted: Dictionary = sim.production._commit_native_n21(dock)
    if not accepted.get("ok", false):
        _fail("N21 rejected exact canonical staged dock World " + str(accepted))
        return
    var frozen: Dictionary = sim.production.snapshot()
    if frozen != before:
        _fail("N21 no-delta commit changed source World/ledger")
        return
    dock["world"]["markets"][market_id]["prices"][commodity] = -99.0
    var ship_ids: Array = world["ships"].keys()
    ship_ids.sort()
    dock["world"]["ships"][str(ship_ids[0])]["credits"] = -10
    dock["world"]["dock_receipts"]["forged"] = {"id": "forged"}
    dock["ledger_snapshot"]["balances"].clear()
    if sim.production.snapshot() != frozen:
        _fail("external N21 proposal still aliases canonical state")
        return
    print("P2_N39_OWNED_MARKET_DOCK_WRITE_SET_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N39_OWNED_MARKET_DOCK_WRITE_SET_FAIL: " + reason)
    quit(1)
