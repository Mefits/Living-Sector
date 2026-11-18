extends SceneTree
## Small manual-control regression for the single native N158 owner.
## NO spawning of fake goods, no parallel World, no GitHub Actions.
## Run: godot --headless --path godot --script res://tests/p2_player_manual_control_check.gd
const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed missing: " + str(seed["error"]))
        return
    var sim = Runner.new()
    if not sim.start_from_seed(seed):
        _fail("boot failed: " + sim.boot_error())
        return
    var fid: String = "terran-authority"
    var other: String = "ceti-freeholds"
    if not sim.player_control_snapshot().get("manual_factions", {}).is_empty():
        _fail("default mode must remain source AI")
        return
    if sim.request_player_control("not-a-faction", true).get("ok", false):
        _fail("unknown faction gained authority")
        return
    var original: Dictionary = sim.checkpoint()["native_production"]
    var control: Dictionary = sim.request_player_control(fid, true)
    if not control.get("ok", false) or not bool(sim.player_control_snapshot()[
            "manual_factions"].get(fid, false)) or bool(sim.player_control_snapshot()[
            "manual_factions"].get(other, false)):
        _fail("manual mode not isolated to selected faction")
        return
    # Building before a committed tick or while unpaused is always denied.
    var early: Dictionary = sim.request_player_construction(
        fid, "earth-station", "food")
    if early.get("ok", false) or str(early.get("reason", "")) != (
            "player_build_requires_paused_paid_tick"):
        _fail("unpaused construction bypass")
        return
    if sim.checkpoint()["native_production"] != original:
        _fail("manual mode or rejected construction changed N39/N9")
        return
    if not sim.queue_control("pause") or not sim.queue_control("step", 1):
        _fail("source clock control refused")
        return
    sim.advance_frame(0.0)
    if sim.tick_count != 1 or not sim.clock.paused or (
            not sim.last_phase_failure().is_empty()):
        _fail("single source tick failed")
        return
    var before: Dictionary = sim.checkpoint()
    # The player cannot commission other factions or unimplemented buildings.
    if sim.request_player_construction(other, "earth-station",
            "food").get("ok", false):
        _fail("foreign uncontrolled faction gained manual authority")
        return
    var absent: Dictionary = sim.request_player_construction(
        fid, "earth-station", "spaceport")
    if absent.get("ok", false) or str(absent.get("reason", "")) != (
            "t1_building_not_implemented"):
        _fail("unimplemented spaceport was treated as buildable")
        return
    var wrong_place: Dictionary = sim.request_player_construction(
        fid, "no-such-station", "food")
    if wrong_place.get("ok", false):
        _fail("site without owned station gained authority")
        return
    if sim.checkpoint()["native_production"] != before["native_production"]:
        _fail("rejected order mutated physical World/N9")
        return
    if not before.has("player_manual_factions") or (
            not bool(before["player_manual_factions"].get(fid, false))):
        _fail("N38 checkpoint omitted player control")
        return
    var swapped: Dictionary = sim.request_player_control(fid, false)
    if not swapped.get("ok", false) or sim.player_control_snapshot()[
            "manual_factions"].has(fid):
        _fail("manual control did not release AI")
        return
    if not sim.restore_checkpoint(before, seed) or (
            not bool(sim.player_control_snapshot().get(
                "manual_factions", {}).get(fid, false))):
        _fail("N38 did not restore per-faction manual authority")
        return
    print("P2_PLAYER_MANUAL_CONTROL_GUARDS_PASS")
    quit(0)

func _fail(message: String) -> void:
    push_error("P2_PLAYER_MANUAL_CONTROL_GUARDS_FAIL " + message)
    quit(1)
