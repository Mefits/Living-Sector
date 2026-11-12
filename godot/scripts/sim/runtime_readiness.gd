extends RefCounted
## N62: read-only P1 readiness gate. No economic or fleet execution.
## Keep diagnostics separate from the authoritative TickRunner and UI.
const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/tick_runner.gd")
const EXPECTED_STATS = {
    "systems": 8, "factions": 3, "bodies": 47,
    "facilities": 15, "ships": 24, "markets": 3, "populations": 3
}
const P1_PHASES = PackedStringArray(["bodies"])

static func audit_seed(seed: Dictionary) -> Dictionary:
    var errors: Array[String] = []
    if seed.has("error"):
        errors.append("seed_import_error")
    var stats_value: Variant = seed.get("seed_stats", null)
    if not (stats_value is Dictionary):
        errors.append("seed_stats_missing")
    else:
        for key in EXPECTED_STATS.keys():
            var observed: Variant = stats_value.get(key, null)
            if not (observed is int) or observed != EXPECTED_STATS[key]:
                errors.append("seed_count_" + key)
    var worlds_value: Variant = seed.get("worlds", null)
    if not (worlds_value is Array):
        errors.append("worlds_missing")
    elif worlds_value.size() != EXPECTED_STATS["systems"]:
        errors.append("world_count")
    var factions_value: Variant = seed.get("factions", null)
    if not (factions_value is Array):
        errors.append("factions_missing")
    elif factions_value.size() != EXPECTED_STATS["factions"]:
        errors.append("faction_count")
    errors.sort()
    return {"ok": errors.is_empty(), "errors": errors}

static func audit_runner(runner: RefCounted) -> Dictionary:
    var errors: Array[String] = []
    if runner == null or not runner.is_started():
        errors.append("runner_not_started")
    else:
        if runner.implemented_phases() != P1_PHASES:
            errors.append("phase_scope_mismatch")
        if runner.tick_count < 0:
            errors.append("negative_tick")
        if runner.world == null or not runner.world.is_loaded():
            errors.append("world_not_loaded")
        else:
            var stats: Dictionary = runner.world.seed_stats()
            for key in EXPECTED_STATS.keys():
                if stats.get(key, null) != EXPECTED_STATS[key]:
                    errors.append("world_count_" + key)
        var checkpoint: Dictionary = runner.checkpoint()
        if checkpoint.get("scenario", "") != "galaxy-067":
            errors.append("scenario_mismatch")
        if checkpoint.get("tick", -1) != runner.tick_count:
            errors.append("checkpoint_tick_mismatch")
        if checkpoint.get("schema_version", -1) != 1:
            errors.append("schema_mismatch")
        if str(checkpoint.get("seed_fingerprint", "")).is_empty():
            errors.append("fingerprint_missing")
    errors.sort()
    return {"ok": errors.is_empty(), "errors": errors}

static func audit_project() -> Dictionary:
    var errors: Array[String] = []
    var scene_path: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
    if scene_path != "res://scenes/main.tscn":
        errors.append("unexpected_main_scene")
    if not ResourceLoader.exists("res://scenes/main.tscn"):
        errors.append("main_scene_missing")
    if not ResourceLoader.exists("res://scripts/main.gd"):
        errors.append("main_script_missing")
    errors.sort()
    return {"ok": errors.is_empty(), "errors": errors}

static func run_preflight() -> Dictionary:
    var project: Dictionary = audit_project()
    var seed: Dictionary = NativeData.load_current_world()
    var seed_report: Dictionary = audit_seed(seed)
    var runner_report: Dictionary = {"ok": false, "errors": ["seed_not_booted"]}
    if seed_report["ok"]:
        var runner = Runner.new()
        if runner.start_from_seed(seed):
            runner_report = audit_runner(runner)
        else:
            runner_report = {"ok": false, "errors": ["runner_boot_failed"]}
    return {
        "ok": project["ok"] and seed_report["ok"] and runner_report["ok"],
        "project": project, "seed": seed_report, "runner": runner_report,
        "scope": "P1 orbital-only; no economy, fleet, contracts or AI runtime verification"
    }
