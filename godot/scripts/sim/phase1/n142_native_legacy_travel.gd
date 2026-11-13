extends RefCounted
## N142 — frozen Rust sim_core/world/travel.rs, with TickConfig formulas from
## sim_core/simulation/config.rs. Legacy *schedule/ETA* arithmetic only.
## Ships in the current Rust world actually pursue moving targets via
## agents/ship/mod.rs::advance_transits; this file NEVER advances a ship.
const U32_MAX: int = 4294967295
const I64_MAX: int = 9223372036854775807
const TICK_CONFIG_DEFAULT := {"ticks_per_second": 8, "world_speed": 0.25}

static func default_tick_config() -> Dictionary:
	return TICK_CONFIG_DEFAULT.duplicate(true)

static func _valid_tick_config(cfg: Dictionary) -> bool:
	var tps = cfg.get("ticks_per_second")
	var speed = cfg.get("world_speed")
	if typeof(tps) != TYPE_INT or int(tps) < 1 or int(tps) > U32_MAX:
		return false
	if typeof(speed) not in [TYPE_FLOAT, TYPE_INT]:
		return false
	return is_finite(float(speed)) and float(speed) > 0.0

static func tick_interval_ms(cfg: Dictionary) -> Dictionary:
	## Rust 1000 / ticks_per_second integer division; for tps > 1000,
	## an interval of zero is possible in source (not a valid UI timer).
	if not _valid_tick_config(cfg):
		return _error("invalid_tick_config")
	return _ok(int(1000 / int(cfg["ticks_per_second"])))

static func tick_scale(cfg: Dictionary) -> Dictionary:
	## Rust world_speed / ticks_per_second as f32.
	if not _valid_tick_config(cfg):
		return _error("invalid_tick_config")
	return _ok(float(cfg["world_speed"]) / float(cfg["ticks_per_second"]))

static func tick_multiplier(cfg: Dictionary) -> Dictionary:
	## Rust (tps as f32 / world_speed).round() as u32.
	## Rust casts saturate on u32; Godot float is effectively f64, so
	## exact f32 rounding edge cases need parity check in Phase 2.
	if not _valid_tick_config(cfg):
		return _error("invalid_tick_config")
	var ratio: float = float(cfg["ticks_per_second"]) / float(cfg["world_speed"])
	if is_nan(ratio):
		return _error("nonfinite_multiplier")
	if is_inf(ratio):
		return _ok(U32_MAX)
	return _ok(int(clampf(round(ratio), 0.0, float(U32_MAX))))

static func travel_ticks(distance: int, speed_modifier: float, cfg: Dictionary) -> Dictionary:
	## Rust:
	## ((distance as f32 * config.tick_multiplier() as f32)
	##    / speed_modifier.max(0.1)) as u64
	## The result is truncated toward zero. Saturation of Rust u64 to
	## i64 is a platform boundary: reject rather than wrap silently.
	if distance < 0 or distance > U32_MAX or not is_finite(speed_modifier):
		return _error("invalid_distance_or_speed")
	var mult := tick_multiplier(cfg)
	if not bool(mult.get("ok", false)):
		return mult
	var base: float = float(mult["value"])
	var count: float = float(distance) * base / maxf(speed_modifier, 0.1)
	if is_nan(count) or count < 0.0:
		return _error("invalid_travel_duration")
	if is_inf(count) or count >= float(I64_MAX):
		return _error("travel_duration_exceeds_godot_i64")
	return _ok(int(count))

static func arrival_tick(departure_tick: int, distance: int, speed_modifier: float, cfg: Dictionary) -> Dictionary:
	## Rust original adds travel_ticks to an unsigned departure tick.
	## Reject signed Godot overflow; NEVER silently wrap to old tick.
	if departure_tick < 0:
		return _error("invalid_departure_tick")
	var result := travel_ticks(distance, speed_modifier, cfg)
	if not bool(result.get("ok", false)):
		return result
	var duration: int = int(result["value"])
	if duration > I64_MAX - departure_tick:
		return _error("arrival_tick_exceeds_godot_i64")
	return _ok(departure_tick + duration)

static func transit_progress(current_tick: int, departure_tick: int, scheduled_arrival: int) -> Dictionary:
	## Native world/travel.rs::transit_progress. This is a display
	## interpolation of a *scheduled* legacy transit, NOT dynamic
	## ShipTransit moving-body navigation.
	if current_tick < 0 or departure_tick < 0 or scheduled_arrival < 0:
		return _error("invalid_transit_timing")
	if scheduled_arrival <= departure_tick:
		return _ok(1.0)
	var elapsed: float = float(maxi(0, current_tick - departure_tick))
	var total: float = float(scheduled_arrival - departure_tick)
	return _ok(clampf(elapsed / total, 0.0, 1.0))

static func _ok(value: Variant) -> Dictionary:
	return {"ok": true, "reason": "", "value": value}

static func _error(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "value": null}
