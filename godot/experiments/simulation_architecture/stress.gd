extends SceneTree
## Large, deterministic, headless performance/consistency stress suite.
## NO scene nodes, UI, extra goods, synthetic wages or fake AI.
const Runner = preload("res://experiments/simulation_architecture/benchmark_runner.gd")
const DIR: String = "res://experiments/simulation_architecture/results"
const JSON_PATH: String = DIR + "/stress.json"
const CSV_PATH: String = DIR + "/stress.csv"
const LOG_PATH: String = DIR + "/stress.log"

var _report: Dictionary = {}
var _log_file: FileAccess
var _failures: Array[String] = []
var _total_samples: int = 0
var _finished_samples: int = 0

func _initialize() -> void:
    var options: Dictionary = {"profile": "stress", "repeats": 3, "seeds": 2}
    for argument in OS.get_cmdline_user_args():
        if not argument.begins_with("--") or not argument.contains("="):
            _failures.append("Invalid argument: " + argument)
            continue
        var pair: PackedStringArray = argument.trim_prefix("--").split("=", false, 1)
        var key: String = pair[0]
        var value: String = pair[1]
        if key == "profile":
            options["profile"] = value
        elif key == "repeats" or key == "seeds":
            if value.is_valid_int():
                options[key] = int(value)
            else:
                _failures.append("Invalid integer for " + key)
        else:
            _failures.append("Unknown argument: " + key)
    var profile: String = str(options["profile"])
    if not ["quick", "stress", "extreme"].has(profile):
        _failures.append("Profile must be quick, stress or extreme")
    if int(options["repeats"]) < 1 or int(options["repeats"]) > 10:
        _failures.append("repeats must be 1..10")
    if int(options["seeds"]) < 1 or int(options["seeds"]) > 5:
        _failures.append("seeds must be 1..5")
    if not _failures.is_empty():
        for error in _failures:
            push_error("SIM_STRESS_INVALID " + error)
        quit(2)
        return

    var absolute_directory: String = ProjectSettings.globalize_path(DIR)
    if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
        push_error("SIM_STRESS cannot create results directory: " + absolute_directory)
        quit(2)
        return
    _log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
    if _log_file == null:
        push_error("SIM_STRESS cannot write log: " + LOG_PATH)
        quit(2)
        return

    var cases: Array[Dictionary] = _make_cases(profile)
    var total: int = cases.size() * int(options["seeds"]) * int(options["repeats"]) * 3
    _total_samples = total
    _report = {
        "kind": "Living Sector scheduler physical N73/N9 stress",
        "status": "RUNNING", "options": options.duplicate(true),
        "source_base_sha": "5a036bf037f0909be5f0f6b5d192049934eef414",
        "scope": "N73 fractional recipes and N9 physical cargo only; NO AI/contracts/payroll",
        "timing_scope": "scheduler runtime measured by benchmark_runner.gd, excludes setup, stock audit, checksum and JSON/CSV writes",
        "stock_scope": "finite inventory seeded at time zero; no infinite resource spawn",
        "cases": [], "failures": [],
        "completed_samples": 0, "expected_samples": total
    }
    _say("SIM_STRESS_BEGIN profile=" + profile +
        " cases=" + str(cases.size()) + " measurements=" + str(total))
    _say("All modes must produce equal complete states for EVERY seed and repeat.")
    if profile == "extreme":
        _say("WARNING: extreme may be computationally expensive. Ctrl+C aborts; partial stress.json remains.")

    _save()
    for case_index in range(cases.size()):
        if not _execute_case(cases[case_index], case_index,
                int(options["seeds"]), int(options["repeats"])):
            _report["status"] = "FAIL"
            _report["failures"] = _failures.duplicate()
            _save()
            _say("SIM_STRESS_FAIL " + JSON.stringify(_failures))
            _log_file.close()
            quit(1)
            return

    _report["status"] = "PASS"
    _report["failures"] = _failures.duplicate()
    _save()
    _say("SIM_STRESS_PASS All " + str(_finished_samples) +
        " measurements completed with identical states per scenario.")
    _say("JSON: " + ProjectSettings.globalize_path(JSON_PATH))
    _say("CSV:  " + ProjectSettings.globalize_path(CSV_PATH))
    _log_file.close()
    quit(0)

func _make_cases(profile: String) -> Array[Dictionary]:
    if profile == "quick":
        return [
            {"name": "dense_1000", "plants": 1000, "ships": 250,
                "days": 365, "stock": "supplied"},
            {"name": "scarce_5000", "plants": 5000, "ships": 750,
                "days": 365, "stock": "starved"}
        ]
    if profile == "extreme":
        return [
            {"name": "dense_20000", "plants": 20000, "ships": 4000,
                "days": 365, "stock": "supplied"},
            {"name": "scarce_20000", "plants": 20000, "ships": 4000,
                "days": 3650, "stock": "starved"},
            {"name": "marathon_5000", "plants": 5000, "ships": 1000,
                "days": 36500, "stock": "normal"}
        ]
    return [
        {"name": "dense_1000", "plants": 1000, "ships": 250,
            "days": 730, "stock": "supplied"},
        {"name": "scarce_5000", "plants": 5000, "ships": 1000,
            "days": 3650, "stock": "starved"},
        {"name": "freight_5000", "plants": 5000, "ships": 2000,
            "days": 730, "stock": "normal"},
        {"name": "dense_5000", "plants": 5000, "ships": 1000,
            "days": 730, "stock": "supplied"},
        {"name": "marathon_1000", "plants": 1000, "ships": 200,
            "days": 3650, "stock": "normal"}
    ]

func _execute_case(config: Dictionary, case_index: int,
        seed_count: int, repeats: int) -> bool:
    var name: String = str(config["name"])
    var samples: Dictionary = {"tick": [], "event": [], "hybrid": []}
    var seed_base: int = 42 + case_index * 101
    _say("CASE_START " + name +
        " plants=" + str(config["plants"]) +
        " ships=" + str(config["ships"]) +
        " days=" + str(config["days"]) +
        " initial_stock=" + str(config["stock"]))
    for seed_index in range(seed_count):
        var seed: int = seed_base + seed_index * 7919
        for repetition in range(repeats):
            # Rotate order to reduce systematic thermal/caching advantages.
            var order: Array[String] = ["tick", "event", "hybrid"]
            var rotate: int = (seed_index + repetition) % 3
            for i in range(rotate):
                order.append(order.pop_front())
            var results: Dictionary = {}
            var run_error: String = ""
            for mode in order:
                _say("RUN " + str(_finished_samples + 1) + "/" +
                    str(_total_samples) + " case=" + name +
                    " seed=" + str(seed) + " repeat=" + str(repetition + 1) +
                    " mode=" + mode)
                var result: Dictionary = Runner.run(
                    mode, int(config["plants"]), int(config["ships"]),
                    int(config["days"]), seed, str(config["stock"]))
                _finished_samples += 1
                _report["completed_samples"] = _finished_samples
                if not result.get("ok", false):
                    run_error = name + "/" + mode + " stock audit: " + str(result.get("error", "unknown"))
                    _failures.append(run_error)
                    _save()
                    return false
                results[mode] = result
                var metrics: Dictionary = {
                    "seed": seed, "repeat": repetition + 1,
                    "milliseconds": float(result["microseconds"]) / 1000.0,
                    "checks": int(result["checks"]),
                    "events": int(result["events"]),
                    "queue_peak": int(result["queue_peak"]),
                    "production_attempts": int(result["attempts"]),
                    "batches": int(result["batches"]),
                    "arrivals": int(result["arrivals"]),
                    "final_active": int(result["final_active"]),
                    "sha256": JSON.stringify(result["state"]).sha256_text()
                }
                samples[mode].append(metrics)
                _say("RESULT " + name + "/" + mode +
                    " ms=" + str(metrics["milliseconds"]) +
                    " batches=" + str(metrics["batches"]) +
                    " arrivals=" + str(metrics["arrivals"]) +
                    " active=" + str(metrics["final_active"]))
                # Persist progress after each mode, so an interrupted run
                # still has a recoverable record of completed measurements.
                _report["in_progress"] = {
                    "case": name, "seed": seed, "repeat": repetition + 1,
                    "mode": mode, "last_metrics": metrics}
                _save()
            var reference: Dictionary = results["tick"]["state"]
            for mode in ["event", "hybrid"]:
                if results[mode]["state"] != reference:
                    _failures.append(name + "/" + mode +
                        " differs from tick at seed=" + str(seed) +
                        " repeat=" + str(repetition + 1))
                    return false
            if results["event"]["attempts"] != results["tick"]["attempts"]:
                _failures.append(name + " event executes different number of production checks")
                return false
            _say("PARITY_PASS " + name + " seed=" + str(seed) +
                " repeat=" + str(repetition + 1))

    var medians: Dictionary = {}
    for mode in ["tick", "event", "hybrid"]:
        var timings: Array[float] = []
        for sample in samples[mode]:
            timings.append(float(sample["milliseconds"]))
        medians[mode] = _median(timings)
    var baseline: float = maxf(float(medians["tick"]), 0.000001)
    var summary: Dictionary = {
        "case": config.duplicate(true), "samples": samples,
        "median_ms": medians,
        "event_relative_to_tick": float(medians["event"]) / baseline,
        "hybrid_relative_to_tick": float(medians["hybrid"]) / baseline,
        "correctness": "PARITY_PASS",
        "sample_count_per_mode": seed_count * repeats
    }
    _report["cases"].append(summary)
    _report.erase("in_progress")
    _save()
    _say("CASE_PASS " + name + " median ms: tick=" +
        str(medians["tick"]) + " event=" + str(medians["event"]) +
        " hybrid=" + str(medians["hybrid"]))
    return true

func _median(values: Array[float]) -> float:
    values.sort()
    var count: int = values.size()
    if count % 2 == 1:
        return values[count / 2]
    return (values[count / 2 - 1] + values[count / 2]) / 2.0

func _save() -> void:
    var json_file: FileAccess = FileAccess.open(JSON_PATH, FileAccess.WRITE)
    if json_file != null:
        json_file.store_string(JSON.stringify(_report, "\t"))
        json_file.close()
    var csv_file: FileAccess = FileAccess.open(CSV_PATH, FileAccess.WRITE)
    if csv_file == null:
        return
    csv_file.store_line("case,plants,ships,days,stock,measurements,tick_median_ms,event_median_ms,hybrid_median_ms,event_over_tick,hybrid_over_tick,parity")
    for summary in _report["cases"]:
        var cfg: Dictionary = summary["case"]
        var med: Dictionary = summary["median_ms"]
        var columns: PackedStringArray = PackedStringArray([
            str(cfg["name"]), str(cfg["plants"]), str(cfg["ships"]),
            str(cfg["days"]), str(cfg["stock"]),
            str(summary["sample_count_per_mode"]),
            str(med["tick"]), str(med["event"]), str(med["hybrid"]),
            str(summary["event_relative_to_tick"]),
            str(summary["hybrid_relative_to_tick"]),
            str(summary["correctness"])
        ])
        csv_file.store_line(columns.join(","))
    csv_file.close()

func _say(message: String) -> void:
    print(message)
    if _log_file != null:
        _log_file.store_line(message)
        _log_file.flush()
