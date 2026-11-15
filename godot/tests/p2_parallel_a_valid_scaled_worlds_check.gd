extends SceneTree
## A7: valid 24/100/500-owned-ship synthetic scale fixture, not game income.
## Every added actor has a unique ID and an N9 wallet sourced from Schema.
## Zero synthetic commerce, orders, movement or revenue is ever committed.
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const DockLocal = preload("res://scripts/sim/phase1/n39_dock_delta_validator.gd")

func _initialize() -> void:
    var sim = Runtime.new()
    if not sim.start_from_seed(Native.load_current_world()):
        _fail("original Galaxy seed cannot start")
        return
    var initial: Dictionary = sim.production.snapshot()
    var seed_world: Dictionary = initial["world"]
    if seed_world["ships"].size() != 24 or Schema.validate(seed_world) != "":
        _fail("original 24-ship source World invalid")
        return
    var eligible: Dictionary = {}
    var selected: String = ""
    var ids: Array = seed_world["ships"].keys()
    ids.sort()
    for sid in ids:
        var candidate: Dictionary = seed_world["ships"][sid]
        if not str(candidate.get("active_contract_id", "")).is_empty() or (
                not str(candidate.get("docked_at", "")).is_empty()) or (
                not (candidate.get("transit", {}) is Dictionary)) or (
                not candidate["transit"].is_empty()):
            continue
        var dock_nearby: bool = false
        for fid in seed_world["facilities"]:
            var fac: Dictionary = seed_world["facilities"][fid]
            if str(fac.get("location", "")) == str(candidate.get("location", "")) and (
                    int(fac.get("docking_capacity", 0)) > 0):
                dock_nearby = true
                break
        if dock_nearby:
            selected = str(sid)
            eligible = candidate
            break
    if eligible.is_empty():
        _fail("no idle noncontracting real source template")
        return
    for total_ships in [24, 100, 500]:
        var world: Dictionary = seed_world.duplicate(true)
        if total_ships > 24:
            for num in range(total_ships - 24):
                var sid: String = "p2a-fixture-ship-%04d" % num
                var clone: Dictionary = eligible.duplicate(true)
                clone["id"] = sid
                if clone.has("name"):
                    clone["name"] = "P2 A Fixture " + str(num)
                clone["active_contract_id"] = ""
                clone["transit"] = {}
                clone["docked_at"] = ""
                if clone.has("dock_attempt_start_tick"):
                    clone["dock_attempt_start_tick"] = null
                if clone.has("current_bt"):
                    clone["current_bt"] = null
                world["ships"][sid] = clone
        var began: int = Time.get_ticks_usec()
        var issue: String = Schema.validate(world)
        var schema_usec: int = Time.get_ticks_usec() - began
        if not issue.is_empty():
            _fail("extended World failed source Schema at " + str(
                total_ships) + ": " + issue)
            return
        # A7 source Schema and local dock occupancy must reject a
        # truly *occupied* over-capacity dock. A longer waiting FIFO
        # alone is legal and is deliberately not counted as occupancy.
        if total_ships >= 100:
            var target_facility: String = ""
            var capacity: int = 0
            for fid in world["facilities"]:
                var fac: Dictionary = world["facilities"][fid]
                var cap: int = int(fac.get("docking_capacity", 0))
                if cap > 0 and cap + 1 <= total_ships - 24 and (
                        str(fac.get("location", "")) == str(eligible["location"])):
                    target_facility = str(fid)
                    capacity = cap
                    break
            if target_facility.is_empty():
                _fail("no real compatible positive-capacity dock for scale proof")
                return
            var overflowing: Dictionary = world.duplicate(true)
            var docked_count: int = 0
            for sid in overflowing["ships"]:
                if str(sid).begins_with("p2a-fixture-ship-"):
                    overflowing["ships"][sid]["docked_at"] = target_facility
                    docked_count += 1
                    if docked_count >= capacity + 1:
                        break
            if DockLocal.validate_delta(world, overflowing, {}) != (
                    "dock_capacity_exceeded") or Schema.validate(overflowing) != (
                    "dock_capacity_exceeded"):
                _fail("local and full Schema differ on occupied docking capacity")
                return
        var accounts: Dictionary = Schema.accounts(world)
        for sid in world["ships"]:
            if not accounts.has(Schema.ship_account(str(sid))) or (
                    accounts[Schema.ship_account(str(sid))] != world["ships"][sid]["credits"]):
                _fail("fixture missed real credit account for " + str(sid))
                return
        var owner := N39.new()
        if not owner.initialize(world):
            _fail("N39 rejected Schema-valid bounded ship roster " + str(total_ships))
            return
        var frame: Dictionary = owner.snapshot()
        if frame["world"]["ships"].size() != total_ships or (
                frame["ledger"]["balances"].size() != accounts.size()):
            _fail("world / ledger account count mismatch in scaled owned fixture")
            return
        began = Time.get_ticks_usec()
        var stage: Dictionary = {"ok": true, "changed": false,
            "status": "unchanged", "expected_n21_version": owner.n21_write_version(),
            "world": frame["world"].duplicate(true),
            "ledger_snapshot": frame["ledger"].duplicate(true)}
        if DockLocal.validate_delta(frame["world"],
                stage["world"], stage["ledger_snapshot"]) != "":
            _fail("local N21 rejects unchanged valid 500/100 World")
            return
        var commit: Dictionary = owner._commit_native_n21(stage)
        var n21_usec: int = Time.get_ticks_usec() - began
        if not commit.get("ok", false):
            _fail("strict N21/N9 refused real-account no-delta scaled World: " + str(commit))
            return
        if owner.snapshot() != frame:
            _fail("no-delta paid N21 ledger mutated source fixture")
            return
        stage["world"]["ships"][selected]["credits"] = -999
        if owner.snapshot() != frame:
            _fail("external N21 proposal escaped detached domain ownership")
            return
        var after := N39.new()
        if not after.restore(frame) or var_to_bytes(after.snapshot()) != var_to_bytes(frame):
            _fail("N38 full bytes diverged on scaled N39/N9")
            return
        print("P2_PARALLEL_A_SCALE_RESULT ships=" + str(total_ships) +
            " wallets=" + str(accounts.size()) +
            " schema_usec=" + str(schema_usec) +
            " n21_guard_usec=" + str(n21_usec) +
            " same_full_frame=true no_alias=true")
    print("P2_PARALLEL_A_VALID_24_100_500_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PARALLEL_A_VALID_24_100_500_FAIL: " + reason)
    quit(1)
