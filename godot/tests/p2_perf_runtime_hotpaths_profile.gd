extends SceneTree
## Original N158/N39 World with the same Rust seed. LOCAL-ONLY
## instrumentation: no scenario edits, no fake ship motion, N38 disk
## save and restore at tick360. Measurements are intentionally not
## part of authoritative World, N9 or the N38 format.
##
## Godot 4.7.2 console:
## godot --headless --path godot --script res://tests/p2_perf_runtime_hotpaths_profile.gd -- --ticks=420
## Repeat with --ticks=1000 / --ticks=10000 and --frame=original
## The "original" switch reverses only the new S5 frame reuse, not
## all other code changes; never report it as full original-commit A/B.
const Native = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Saves = preload("res://scripts/sim/save_state.gd")
const NativeFrame = preload("res://scripts/sim/phase2/unified_native_save_roundtrip_guard.gd")

const CHECKPOINT_TICKS: Array[int] = [1, 60, 120, 240, 360, 361,
    420, 825, 1000, 2000, 5000, 10000]

func _initialize() -> void:
    var limit: int = 420
    var frame_original: bool = false
    var label: String = ""
    for raw in OS.get_cmdline_user_args():
        var arg: String = str(raw)
        if arg.begins_with("--ticks="):
            var value: String = arg.trim_prefix("--ticks=")
            if not value.is_valid_int():
                _fail("invalid ticks argument: " + value)
                return
            limit = int(value)
        elif arg == "--frame=original":
            frame_original = true
        elif arg == "--frame=optimized":
            frame_original = false
        elif arg.begins_with("--label="):
            label = arg.trim_prefix("--label=")
    if limit not in [420, 1000, 10000]:
        _fail("use only --ticks=420, 1000 or 10000")
        return
    if label.is_empty():
        label = "frame_original" if frame_original else "frame_optimized"
    OS.set_environment("LS_PROFILE_NATIVE_PHASES", "1")
    OS.set_environment("LS_PERF_NO_FACTION_FRAME_REUSE",
        "1" if frame_original else "0")
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("missing original Rust seed: " + str(seed))
        return
    var sim = Runner.new()
    if not sim.start_from_seed(seed):
        _fail("N158 failed to boot original seed: " + sim.boot_error())
        return
    if not sim.queue_control("pause") or not sim.queue_control("speed", 8.0):
        _fail("N1 clock setup rejected")
        return
    sim.advance_frame(0.0)
    if not sim.clock.paused or sim.clock.tick_multiplier() != 1:
        _fail("N1 x8 clock or pause not committed")
        return

    var dir: String = ProjectSettings.globalize_path("user://tests")
    if DirAccess.make_dir_recursive_absolute(dir) != OK:
        _fail("cannot create local profiling directory: " + dir)
        return
    var started_us: int = Time.get_ticks_usec()
    var durations: Array = []
    var checkpoints: Array = []
    var segments: Array = []
    var save_path: String = "user://tests/perf-runtime-n38-" + label + ".json"
    var segment_begin: int = 1

    for tick in range(1, limit + 1):
        var t0: int = Time.get_ticks_usec()
        if not sim.queue_control("step", 1):
            _fail("N1 step rejected at " + str(tick))
            return
        sim.advance_frame(0.0)
        var elapsed: int = maxi(0, Time.get_ticks_usec() - t0)
        durations.append(elapsed)
        if sim.tick_count != tick or not sim.last_phase_failure().is_empty():
            _fail("phase stopped at " + str(tick) + " result=" +
                str(sim.last_phase_failure()) + " actual=" + str(sim.tick_count))
            return
        if not CHECKPOINT_TICKS.has(tick) and tick != limit:
            continue
        # Checkpoint/JSON hashing is OUTSIDE measured tick duration.
        var snapshot: Dictionary = sim.checkpoint()
        if snapshot.is_empty() or not snapshot.has("native_production"):
            _fail("N38 checkpoint unavailable at tick=" + str(tick))
            return
        var physical: Dictionary = snapshot["native_production"]["world"]
        var bank: Dictionary = snapshot["native_production"]["ledger"]
        var check: Dictionary = {
            "tick": tick, "checkpoint_sha256": JSON.stringify(
                snapshot, "", true, true).sha256_text(),
            "ships": physical.get("ships", {}).size(),
            "facilities": physical.get("facilities", {}).size(),
            "markets": physical.get("markets", {}).size(),
            "populations": physical.get("populations", {}).size(),
            "construction": physical.get("construction_sites", {}).size(),
            "contracts": physical.get("contract_board", {}).get("contracts", {}).size(),
            "receipts": bank.get("receipts", {}).size()}
        checkpoints.append(check)
        print("LS_PERF_RUNTIME_CHECK tick=", tick, " sha256=",
            str(check["checkpoint_sha256"]), " ships=", int(check["ships"]),
            " receipts=", int(check["receipts"]))
        if tick != 360:
            continue
        if Saves.save_runner(sim, save_path) != OK:
            _fail("real N38 disk save failed at tick360")
            return
        var fresh = Runner.new()
        if not fresh.start_from_seed(seed):
            _fail("fresh N158 boot for N38 restart failed")
            return
        var result: Dictionary = Saves.load_runner(fresh, seed, save_path)
        if not result.get("ok", false) or fresh.tick_count != 360:
            _fail("N38 disk restore failed " + str(result))
            return
        var exact: Dictionary = NativeFrame.verify_authoritative_frame(
            snapshot, fresh.checkpoint())
        if not exact.get("ok", false):
            _fail("N38 authoritative frame mismatch: " + str(exact))
            return
        segments.append({
            "from_tick": segment_begin, "to_tick": tick,
            "native_phases": sim.profile_native_phases(),
            "ship_stages": sim.profile_native_ship_subphases(),
            "n39_schema_and_copies": sim.production.native_schema_profile(),
            "n39_full_copies": sim.production.world_copy_profile()})
        sim = fresh
        segment_begin = tick + 1

    segments.append({
        "from_tick": segment_begin, "to_tick": limit,
        "native_phases": sim.profile_native_phases(),
        "ship_stages": sim.profile_native_ship_subphases(),
        "n39_schema_and_copies": sim.production.native_schema_profile(),
        "n39_full_copies": sim.production.world_copy_profile()})
    var sorted_durations: Array = durations.duplicate()
    sorted_durations.sort()
    var total: int = 0
    for duration in durations:
        total += int(duration)
    var phase_totals: Dictionary = {}
    var phase_calls: Dictionary = {}
    for segment in segments:
        var stats: Dictionary = segment["native_phases"].get("phase_stats", {})
        for phase in stats:
            var row: Dictionary = stats[phase]
            phase_totals[phase] = int(phase_totals.get(phase, 0)) + int(
                row.get("total_usec", 0))
            phase_calls[phase] = int(phase_calls.get(phase, 0)) + int(
                row.get("calls", 0))
    var ranking: Array = []
    for phase in phase_totals:
        ranking.append({"phase": phase, "total_usec": phase_totals[phase],
            "calls": phase_calls[phase]})
    ranking.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return int(a["total_usec"]) > int(b["total_usec"]))
    var p95: int = clampi(ceili(float(sorted_durations.size()) * 0.95) - 1,
        0, sorted_durations.size() - 1)
    var report: Dictionary = {
        "label": label, "mode": "original_faction_frames" if frame_original
            else "optimized_faction_frames",
        "ticks": limit, "n38_restart360_verified": true,
        "checkpoint_states": checkpoints, "segments": segments,
        "phase_ranking": ranking,
        "tick_cost": {"calls": durations.size(),
            "mean_usec": float(total) / float(durations.size()),
            "p95_usec": int(sorted_durations[p95]),
            "max_usec": int(sorted_durations.back()),
            "total_tick_usec": total,
            "wall_with_checkpoints_usec": Time.get_ticks_usec() - started_us},
        "source": "original Galaxy Rust 0.6.7; no artificial fleet",
        "measurement_warning": "Opt-in profiler overhead and disk checkpoints " +
            "are not FPS. Compare runs on the same PC with same seed/speed."}
    var output_path: String = "user://tests/perf-runtime-" + label + "-" + str(limit) + ".json"
    var file = FileAccess.open(output_path, FileAccess.WRITE)
    if file == null:
        _fail("cannot write profiler result: " + output_path)
        return
    file.store_string(JSON.stringify(report, "\t", true, true))
    file.close()
    print("LS_PERF_RUNTIME_PROFILE_PASS ticks=", limit,
        " mean_us=", report["tick_cost"]["mean_usec"],
        " p95_us=", report["tick_cost"]["p95_usec"],
        " max_us=", report["tick_cost"]["max_usec"],
        " phase_ranking=", str(ranking.slice(0, 6)),
        " report=", ProjectSettings.globalize_path(output_path))
    quit(0)

func _fail(message: String) -> void:
    push_error("LS_PERF_RUNTIME_PROFILE_FAIL: " + message)
    quit(1)
