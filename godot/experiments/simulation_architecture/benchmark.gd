extends SceneTree
## Entry point; Godot --headless --path godot --script res://experiments/simulation_architecture/benchmark.gd -- --plants=100 --ships=20 --years=1
const Runner = preload("res://experiments/simulation_architecture/benchmark_runner.gd")
const RESULT_PATH: String = "res://experiments/simulation_architecture/results/latest.json"

func _initialize() -> void:
    var options: Dictionary = {"plants": 100, "ships": 20, "years": 1, "seed": 42}
    var failures: Array[String] = []
    for argument in OS.get_cmdline_user_args():
        if not argument.begins_with("--") or not argument.contains("="):
            failures.append("Unknown option " + argument)
            continue
        var parts: PackedStringArray = argument.trim_prefix("--").split("=", false, 1)
        var key: String = parts[0]
        if not options.has(key) or not parts[1].is_valid_int():
            failures.append("Invalid option " + argument)
            continue
        options[key] = int(parts[1])
    if int(options["plants"]) < 1 or int(options["plants"]) > 5000:
        failures.append("plants must be 1..5000")
    if int(options["ships"]) < 1 or int(options["ships"]) > 1000:
        failures.append("ships must be 1..1000")
    if int(options["years"]) < 1 or int(options["years"]) > 100:
        failures.append("years must be 1..100")
    if int(options["seed"]) < 0 or int(options["seed"]) > 1000000:
        failures.append("seed must be 0..1000000")
    if not failures.is_empty():
        _reject(failures)
        return

    var horizon: int = int(options["years"]) * 365
    var report: Dictionary = {
        "kind": "Living Sector isolated scheduler experiment",
        "scope": "real N73 recipe execute and N9 physical cargo transfer; NOT N39 payroll, N104 contracts or faction AI",
        "base_commit": "5a036bf037f0909be5f0f6b5d192049934eef414",
        "configuration": options.duplicate(true),
        "ticks": horizon, "time_unit": "experimental days; N39 5-tick production cadence",
        "results": [], "equivalent": false, "failures": []
    }
    var baseline: Dictionary = {}
    for mode in ["tick", "event", "hybrid"]:
        var result: Dictionary = Runner.run(mode, int(options["plants"]),
            int(options["ships"]), horizon, int(options["seed"]))
        if not result.get("ok", false):
            failures.append(str(mode) + " failed stock audit: " + str(result.get("error", "?")))
        var state: Dictionary = result.get("state", {})
        var checksum: String = JSON.stringify(state).sha256_text()
        if mode == "tick":
            baseline = state
        elif state != baseline:
            failures.append(str(mode) + " differs from tick's complete final state")
        var metrics: Dictionary = {
            "mode": mode,
            "milliseconds": float(result.get("microseconds", 0)) / 1000.0,
            "checks": result.get("checks", 0), "events": result.get("events", 0),
            "queue_peak": result.get("queue_peak", 0),
            "production_attempts": result.get("attempts", 0),
            "batches": result.get("batches", 0),
            "arrivals": result.get("arrivals", 0),
            "sha256": checksum
        }
        report["results"].append(metrics)
        print("SIM_BENCH ", JSON.stringify(metrics))
    # Intermediate state checks catch timing differences hidden by matching endpoints.
    var checkpoints: Array = []
    for checkpoint in [5, 10, 30, 365]:
        if checkpoint >= horizon:
            continue
        var baseline_at_tick: Dictionary = Runner.run(
            "tick", int(options["plants"]), int(options["ships"]),
            checkpoint, int(options["seed"]))
        if not baseline_at_tick.get("ok", false):
            failures.append("tick audit at checkpoint " + str(checkpoint))
            continue
        for other in ["event", "hybrid"]:
            var candidate_at_tick: Dictionary = Runner.run(
                other, int(options["plants"]), int(options["ships"]),
                checkpoint, int(options["seed"]))
            if not candidate_at_tick.get("ok", false):
                failures.append(str(other) + " audit at checkpoint " + str(checkpoint))
            elif candidate_at_tick["state"] != baseline_at_tick["state"]:
                failures.append(str(other) + " diverges at tick " + str(checkpoint))
        checkpoints.append(checkpoint)
    report["checked_intermediate_ticks"] = checkpoints
    report["equivalent"] = failures.is_empty()
    report["failures"] = failures.duplicate()
    var local_path: String = ProjectSettings.globalize_path(
        "res://experiments/simulation_architecture/results")
    var dir_result: Error = DirAccess.make_dir_recursive_absolute(local_path)
    if dir_result != OK:
        failures.append("cannot_create_report_dir_" + str(dir_result))
    else:
        var file: FileAccess = FileAccess.open(RESULT_PATH, FileAccess.WRITE)
        if file == null:
            failures.append("cannot_write_report_" + str(FileAccess.get_open_error()))
        else:
            report["equivalent"] = failures.is_empty()
            report["failures"] = failures.duplicate()
            file.store_string(JSON.stringify(report, "\t"))
            file.close()

    if failures.is_empty():
        print("SIM_BENCH_PASS ", RESULT_PATH)
        quit(0)
    else:
        _reject(failures)

func _reject(failures: Array[String]) -> void:
    for message in failures:
        push_error("SIM_BENCH_FAIL " + message)
    quit(1)
