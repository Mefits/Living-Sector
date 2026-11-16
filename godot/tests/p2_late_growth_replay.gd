extends SceneTree
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs/late-growth"))
    var path: String = OS.get_environment("LS_LATE_RESUME")
    var input = FileAccess.open(path, FileAccess.READ)
    var seed: Dictionary = Native.load_current_world()
    var sim = Runtime.new()
    if input == null or not sim.start_from_seed(seed) or not sim.restore_checkpoint(input.get_var(), seed):
        push_error("restore failed")
        quit(1)
        return
    var first: int = sim.tick_count
    var costs: Array = []
    Ledger.profile_cost = {}
    var trace: Array[String] = []
    for index in range(32):
        sim.queue_control("step", 1)
        var t: int = Time.get_ticks_usec()
        sim.advance_frame(0.0)
        costs.append(Time.get_ticks_usec() - t)
        if sim.tick_count != first + index + 1 or not sim.last_phase_failure().is_empty():
            push_error(str(sim.last_phase_failure()))
            quit(1)
            return
        var measured_ledger: Dictionary = Ledger.profile_cost.duplicate(true)
        trace.append(JSON.stringify(sim.checkpoint(), "", true, true).sha256_text())
        Ledger.profile_cost = measured_ledger
    var label: String = OS.get_environment("LS_LATE_LABEL")
    var result: Dictionary = {"from": first, "tick": sim.tick_count, "costs_us": costs, "trace": trace,
        "ledger": Ledger.profile_cost.duplicate(true), "phases": sim.phase_metrics(),
        "schema": sim.production.native_schema_profile()}
    var snapshot: Dictionary = sim.checkpoint()
    result["digest"] = JSON.stringify(snapshot,"",true,true).sha256_text()
    var f = FileAccess.open("res://logs/late-growth/ls-replay-" + label + "-" + str(first) + ".bin",FileAccess.WRITE)
    f.store_var(snapshot)
    f.close()
    f = FileAccess.open("res://logs/late-growth/ls-replay-" + label + "-" + str(first) + ".json",FileAccess.WRITE)
    f.store_string(JSON.stringify(result))
    print("LATE_REPLAY_PASS ",JSON.stringify(result))
    quit(0)
