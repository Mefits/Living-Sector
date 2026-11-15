extends RefCounted
## N140: source-derived fixtures for Rust simulation/lod.rs and tuning.rs.
## These are executable in Phase 2; NOT run during the current source-port.
const Lod = preload("res://scripts/sim/phase1/n140_native_spatial_lod.gd")
const Tuning = preload("res://scripts/sim/phase1/n140_native_world_tuning.gd")

static func _check(errors: Array[String], condition: bool, name: String) -> void:
	if not condition:
		errors.append(name)

static func run() -> Dictionary:
	var errors: Array[String] = []
	var r: float = 5.0
	_check(errors, Lod.divisor_for_distance_sq(0.0, r) == 1, "lod_zero")
	_check(errors, Lod.divisor_for_distance_sq(25.0, r) == 1, "lod_radius_inclusive")
	_check(errors, Lod.divisor_for_distance_sq(26.0, r) == 2, "lod_just_outside")
	_check(errors, Lod.divisor_for_distance_sq(100.0, r) == 2, "lod_2r_inclusive")
	_check(errors, Lod.divisor_for_distance_sq(625.0, r) == 5, "lod_5r_inclusive")
	_check(errors, Lod.divisor_for_distance_sq(2500.0, r) == 10, "lod_10r_inclusive")
	_check(errors, Lod.divisor_for_distance_sq(10000.0, r) == 20, "lod_20r_inclusive")
	_check(errors, Lod.divisor_for_distance_sq(12500.0, r) == 50, "lod_far")
	var near := [
		{"position": Vector2(0.0, 0.0), "radius": 1.0},
		{"position": Vector2(10.0, 0.0), "radius": 5.0}
	]
	_check(errors, Lod.divisor_for_position(Vector2(6.0, 0.0), near) == 1, "lod_nearest_observer")
	_check(errors, Lod.divisor_for_position(Vector2(6.0, 0.0), []) == 1, "lod_no_observers")
	var cursor := {"divisor": 5, "next_tick": 10}
	var early := Lod.try_fire(cursor, 9)
	_check(errors, bool(early["ok"]) and not bool(early["fired"]) and int(cursor["next_tick"]) == 10, "cursor_not_due")
	var fire := Lod.try_fire(cursor, 10)
	_check(errors, bool(fire["fired"]) and int(fire["skipped_ticks"]) == 5 and int(fire["cursor"]["next_tick"]) == 15, "cursor_fire")
	var skipped := Lod.try_fire(fire["cursor"], 11)
	_check(errors, not bool(skipped["fired"]), "cursor_skip_between")
	var again := Lod.try_fire(fire["cursor"], 15)
	_check(errors, bool(again["fired"]) and int(again["skipped_ticks"]) == 5, "cursor_next_fire")
	var initial := Lod.try_fire(Lod.new_cursor(), 0)
	_check(errors, bool(initial["fired"]) and int(initial["skipped_ticks"]) == 1, "first_fire_exact_one")
	var past := Lod.set_divisor({"divisor": 50, "next_tick": 95}, 1, 100)
	_check(errors, int(past["cursor"]["next_tick"]) == 100, "cursor_reanchor_past")
	var future := Lod.set_divisor({"divisor": 1, "next_tick": 101}, 10, 100)
	_check(errors, int(future["cursor"]["next_tick"]) == 110, "cursor_reanchor_future")
	var noop := Lod.set_divisor({"divisor": 5, "next_tick": 100}, 5, 90)
	_check(errors, int(noop["cursor"]["next_tick"]) == 100, "cursor_noop")
	# Native ship pass advances only ships; facility/population LOD cursors
	# remain intact. Ships without LOD tick at scale 1.
	var fleet := {
		"ship-a": {"lod": {"divisor": 2, "next_tick": 3}, "position": Vector2(0, 0)},
		"ship-b": {"lod": null, "position": Vector2(0, 0)},
		"facility-a": {"lod": {"divisor": 50, "next_tick": 0}, "position": Vector2(20, 0)}
	}
	var batch := Lod.ship_gate(fleet, ["ship-a", "ship-b"], 3)
	_check(errors, bool(batch["ok"]) and int(batch["fires"].get("ship-b", -1)) == 1 and
		int(batch["fires"].get("ship-a", -1)) == 2, "ship_gate_skipped_ticks")
	_check(errors, int(batch["agents"]["facility-a"]["lod"]["next_tick"]) == 0, "facility_cursor_not_advanced")
	_check(errors, int(fleet["ship-a"]["lod"]["next_tick"]) == 3, "ship_gate_input_immutable")
	var positionless := {"ship-c": {"lod": {"divisor": 5, "next_tick": 100}},
		"ship-a": {"lod": {"divisor": 50, "next_tick": 95}, "position": Vector2(0, 0)}}
	var recompute := Lod.recompute(positionless, near, 100)
	_check(errors, bool(recompute["ok"]) and int(recompute["stats"]["total"]) == 1, "recompute_positionless_not_counted")
	_check(errors, int(recompute["agents"]["ship-a"]["lod"]["next_tick"]) == 100, "recompute_active_at_current_tick")
	_check(errors, int(recompute["agents"]["ship-c"]["lod"]["next_tick"]) == 100, "recompute_does_not_touch_unlocated")
	# WorldTuning::default + serde(default) behavior.
	var tuning_defaults := Tuning.defaults()
	var partial := Tuning.from_json_string("{\"dock_fee_burn_pct\": 0.5, \"unknown_key\": 44}")
	_check(errors, bool(partial["ok"]) and is_equal_approx(float(partial["tuning"]["dock_fee_burn_pct"]), 0.5)
		and int(partial["tuning"]["market_crisis_shortage_ticks"]) == 200, "serde_partial_json")
	_check(errors, bool(tuning_defaults["auto_replace_retired_ships"]) and
		bool(tuning_defaults["regenerate_body_resources"]), "legacy_defaults")
	var genesis := Tuning.from_json_string("{\"auto_replace_retired_ships\":false,\"regenerate_body_resources\":false}")
	var policy := Tuning.physical_genesis_policy(genesis["tuning"])
	_check(errors, bool(policy["ok"]) and not bool(policy["allow_auto_replace_retired_ships"]) and
		not bool(policy["allow_timed_body_regeneration"]), "finite_genesis_has_no_free_resources")
	var tuning_owner = Tuning.new()
	_check(errors, tuning_owner.install_once(genesis["tuning"]), "first_tuning_install")
	_check(errors, not tuning_owner.install_once(tuning_defaults), "once_lock_second_set_ignored")
	_check(errors, not bool(tuning_owner.current()["regenerate_body_resources"]), "once_lock_stays_finite")
	var current_first = Tuning.new()
	_check(errors, current_first.current() == tuning_defaults and
		not current_first.install_once(genesis["tuning"]), "once_lock_default_on_first_read")
	var wrong := Tuning.from_json_string("{\"market_crisis_shortage_ticks\":-1}")
	_check(errors, not bool(wrong["ok"]), "serde_reject_negative_u32")
	_check(errors, Lod.should_recompute(1600, 32), "lod_recompute_interval_native_default")
	return {"ok": errors.is_empty(), "errors": errors}
