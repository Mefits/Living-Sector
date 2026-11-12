extends RefCounted
## N142 — source-derived fixtures for Rust world/registry.rs and world/travel.rs.
## Compiled/executed only in Phase 2; never claim VERIFIED from this file.
const NativeRegistry = preload("res://scripts/sim/phase1/n142_native_world_registry.gd")
const NativeTravel = preload("res://scripts/sim/phase1/n142_native_legacy_travel.gd")

static func _assert(results: Array[String], ok: bool, name: String) -> void:
	if not ok:
		results.append(name)

static func _place(name: String, body: int) -> Dictionary:
	return {"db_id": body, "name": name, "loc_type": "station",
		"celestial_body_id": body}

static func _native_registry() -> Dictionary:
	## Real shape of WorldRegistry, not a guessed UI coordinate graph.
	return {"systems": {
			"sol": {"db_id": 1, "name": "sol",
				"universe_offset": [0.0, 0.0], "star_type": "G"},
			"ac": {"db_id": 2, "name": "ac",
				"universe_offset": [5.0, 2.0], "star_type": null}
		},
		"locations": {
			"alpha": _place("alpha", 1),
			"mid": _place("mid", 2),
			"end": _place("end", 3),
			"gate-sol": _place("gate-sol", 4),
			"gate-ac": _place("gate-ac", 5),
			"isolated": _place("isolated", 6)
		},
		"routes": {
			"alpha": [{"to": "end", "distance": 300}, {"to": "mid", "distance": 125}],
			"mid": [{"to": "alpha", "distance": 125}, {"to": "end", "distance": 22}],
			"end": [{"to": "mid", "distance": 22}],
			"gate-sol": [{"to": "alpha", "distance": 7}]
		},
		"faction_ids": ["civ", "other"]}

static func run() -> Dictionary:
	var failures: Array[String] = []
	var reg = NativeRegistry.new()
	var data := _native_registry()
	_assert(failures, reg.load_native_snapshot(data), "registry_import")
	_assert(failures, reg.system("sol")["star_type"] == "G" and reg.system("ac")["star_type"] == null,
		"system_metadata_optional_spectral")
	_assert(failures, reg.location("end")["celestial_body_id"] == 3, "location_native_body_link")
	var direct := reg.travel_distance("alpha", "end")
	var indirect := reg.shortest_distance("alpha", "end")
	_assert(failures, bool(direct["found"]) and int(direct["distance"]) == 300,
		"travel_distance_remains_one_direct_edge")
	_assert(failures, bool(indirect["found"]) and int(indirect["distance"]) == 147,
		"physical_shortest_prefers_existing_two_legs")
	_assert(failures, int(reg.shortest_distance("end", "alpha")["distance"]) == 147,
		"physical_reverse_requires_explicit_edges")
	_assert(failures, not bool(reg.travel_distance("alpha", "isolated")["found"]),
		"no_fabricated_direct_edge")
	_assert(failures, not bool(reg.shortest_distance("alpha", "isolated")["found"]),
		"unreachable_location_no_invented_distance")
	_assert(failures, not bool(reg.shortest_distance("gate-sol", "gate-ac")["found"]),
		"physical_shortest_must_ignore_gate_pairs")
	_assert(failures, bool(reg.shortest_distance("missing", "missing")["found"]) and
		int(reg.shortest_distance("missing", "missing")["distance"]) == 0,
		"rust_same_location_even_when_unknown")
	var matrix := reg.physical_distance_matrix([
		{"from": "alpha", "to": "end"},
		{"from": "end", "to": "alpha"}
	])
	_assert(failures, bool(matrix["ok"]) and int(matrix["distances"]["alpha"]["end"]) == 147,
		"physical_matrix_for_strategy_dispatch")
	_assert(failures, not bool(reg.physical_distance_matrix([{"from": "missing", "to": "missing"}])["ok"]),
		"physical_matrix_rejects_ghost_system")
	var saved := reg.snapshot()
	var restored = NativeRegistry.new()
	_assert(failures, restored.restore_snapshot(saved) and restored.snapshot() == saved,
		"read_only_registry_snapshot_roundtrip")
	# Input mutation must not alter copied native state.
	data["routes"]["alpha"][0]["distance"] = 1
	_assert(failures, int(reg.travel_distance("alpha", "end")["distance"]) == 300,
		"registry_owns_immutable_copy")
	var bad := saved.duplicate(true)
	bad["routes"]["mid"][0]["to"] = "nonexistent"
	_assert(failures, not reg.load_native_snapshot(bad) and reg.snapshot() == saved,
		"bad_registry_fails_atomically")
	# Rust first-matching direct edge can differ from shortest path on a
	# duplicate DB route; preserve multiset/order, never auto-deduplicate.
	var duplicates := saved.duplicate(true)
	duplicates["routes"]["alpha"].append({"to": "mid", "distance": 20})
	_assert(failures, reg.load_native_snapshot(duplicates) and
		int(reg.travel_distance("alpha", "mid")["distance"]) == 125 and
		int(reg.shortest_distance("alpha", "mid")["distance"]) == 20,
		"first_direct_edge_and_all_dijkstra_edges")
	# Saturating MAX path is not discovered (native cost default is u32::MAX).
	var max_cost := saved.duplicate(true)
	max_cost["routes"]["alpha"] = [{"to": "isolated", "distance": NativeRegistry.U32_MAX}]
	reg.load_native_snapshot(max_cost)
	_assert(failures, not bool(reg.shortest_distance("alpha", "isolated")["found"]),
		"u32_max_saturation_is_not_discovered")
	# Frozen world/travel.rs math. This helper is NOT the moving-body
	# ShipTransit update (Rust agents/ship/mod.rs::advance_transits).
	var cfg := NativeTravel.default_tick_config()
	_assert(failures, int(NativeTravel.tick_interval_ms(cfg)["value"]) == 125,
		"tick_interval_default")
	_assert(failures, is_equal_approx(float(NativeTravel.tick_scale(cfg)["value"]), 0.03125),
		"tick_scale_default")
	_assert(failures, int(NativeTravel.tick_multiplier(cfg)["value"]) == 32,
		"tick_multiplier_default")
	_assert(failures, int(NativeTravel.travel_ticks(60, 1.0, cfg)["value"]) == 1920,
		"travel_ticks_default")
	_assert(failures, int(NativeTravel.travel_ticks(60, 0.6, cfg)["value"]) == 3200,
		"travel_ticks_slow_ship")
	_assert(failures, int(NativeTravel.travel_ticks(60, 1.5, cfg)["value"]) == 1280,
		"travel_ticks_fast_ship")
	_assert(failures, int(NativeTravel.arrival_tick(100, 60, 1.0, cfg)["value"]) == 2020,
		"arrival_tick_departure_offset")
	_assert(failures, is_equal_approx(float(NativeTravel.transit_progress(50, 0, 100)["value"]), 0.5),
		"progress_half")
	_assert(failures, is_equal_approx(float(NativeTravel.transit_progress(150, 0, 100)["value"]), 1.0),
		"progress_clamped")
	_assert(failures, is_equal_approx(float(NativeTravel.transit_progress(50, 100, 100)["value"]), 1.0),
		"progress_zero_duration")
	_assert(failures, not bool(NativeTravel.travel_ticks(60, NAN, cfg)["ok"]),
		"reject_nonnumeric_speed_no_fake_duration")
	return {"ok": failures.is_empty(), "errors": failures}
