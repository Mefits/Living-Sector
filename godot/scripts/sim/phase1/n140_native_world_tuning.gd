extends RefCounted
## N140: source-accurate Rust simulation/tuning.rs WorldTuning.
## Rust uses OnceLock<WorldTuning> (one set at boot, default on first read),
## #[serde(default)] partial JSON and NO runtime admin live editing yet.
## Each object is an isolated world/config owner; the actual Phase-2
## integration must create exactly ONE instance per live World.
const MAX_U32: int = 4294967295
const MAX_I64: int = 9223372036854775807

const BOOL_KEYS := ["auto_replace_retired_ships", "regenerate_body_resources"]
const FLOAT_KEYS := [
	"min_recipe_margin_ratio", "dock_fee_burn_pct",
	"facility_starving_condition", "facility_starving_recovery",
	"fuel_urgency_onset", "replan_score_ratio"
]
const U32_KEYS := ["market_crisis_shortage_ticks", "market_crisis_recovery_ticks"]
const U64_KEYS := ["replan_min_commit_ticks", "replan_check_interval_ticks"]

var _installed: bool = false
var _value: Dictionary = {}

static func defaults() -> Dictionary:
	return {
		"auto_replace_retired_ships": true,
		"regenerate_body_resources": true,
		"min_recipe_margin_ratio": 0.5,
		"dock_fee_burn_pct": 0.30,
		"market_crisis_shortage_ticks": 200,
		"market_crisis_recovery_ticks": 50,
		"facility_starving_condition": 0.3,
		"facility_starving_recovery": 0.5,
		"fuel_urgency_onset": 0.45,
		"replan_min_commit_ticks": 40,
		"replan_check_interval_ticks": 20,
		"replan_score_ratio": 1.30,
	}

static func _type_error(field: String, value: Variant) -> String:
	if field in BOOL_KEYS:
		return "" if typeof(value) == TYPE_BOOL else "expected_bool:" + field
	if field in FLOAT_KEYS:
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT]:
			return "expected_float:" + field
		if not is_finite(float(value)):
			return "nonfinite_float:" + field
		return ""
	if field in U32_KEYS:
		if typeof(value) != TYPE_INT:
			return "expected_u32:" + field
		return "" if int(value) >= 0 and int(value) <= MAX_U32 else "out_of_range_u32:" + field
	if field in U64_KEYS:
		if typeof(value) != TYPE_INT:
			return "expected_u64:" + field
		# GDScript int has signed 64-bit range; Rust u64 > i64::MAX needs
		# an explicit future serialization adapter (no silent wrap).
		return "" if int(value) >= 0 else "out_of_range_u64:" + field
	return "" # serde ignores unrecognized JSON object fields by default.

static func from_object(overrides: Dictionary) -> Dictionary:
	## Rust serde(default): missing values read from Default, unknown ignored.
	## This function DOES NOT enforce gameplay balance constraints that Rust
	## itself does not enforce at deserialize time.
	var values := defaults()
	for key in overrides:
		if not values.has(key):
			continue
		var problem := _type_error(str(key), overrides[key])
		if problem != "":
			return {"ok": false, "reason": problem, "tuning": {}}
		values[key] = overrides[key]
	return {"ok": true, "reason": "", "tuning": values}

static func from_json_string(json_text: String) -> Dictionary:
	## Rust serde_json::from_str supports only an object for WorldTuning.
	var parsed = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		return {"ok": false, "reason": "expected_json_object", "tuning": {}}
	return from_object(parsed)

func install_once(tuning: Dictionary) -> bool:
	## WorldTuning::set silently ignores a second installation. The
	## constructor supplies no invisible default values after validation.
	if _installed:
		return false
	var normalized := from_object(tuning)
	if not bool(normalized.get("ok", false)):
		return false
	_value = normalized["tuning"]
	_installed = true
	return true

func current() -> Dictionary:
	## WorldTuning::current/get_or_init(Default). First read freezes defaults
	## so later set_once() cannot silently replace the world's policy.
	if not _installed:
		_value = defaults()
		_installed = true
	return _value.duplicate(true)

func set_from_json_once(json_text: String) -> Dictionary:
	if _installed:
		return {"ok": false, "reason": "tuning_already_initialized", "tuning": current()}
	var parsed := from_json_string(json_text)
	if not bool(parsed.get("ok", false)):
		return parsed
	_value = parsed["tuning"].duplicate(true)
	_installed = true
	return {"ok": true, "reason": "", "tuning": current()}

func is_installed() -> bool:
	return _installed

static func physical_genesis_policy(tuning: Dictionary) -> Dictionary:
	## Read-only flags for existing Rust production/retirement functions.
	## This helper creates NO ships or deposits. Genesis startup JSON sets
	## both false; legacy worlds use Rust true/true defaults.
	var values := from_object(tuning)
	if not bool(values.get("ok", false)):
		return {"ok": false, "reason": values.get("reason", "")}
	var v: Dictionary = values["tuning"]
	return {"ok": true, "allow_auto_replace_retired_ships": bool(v["auto_replace_retired_ships"]),
		"allow_timed_body_regeneration": bool(v["regenerate_body_resources"])}

static func _same_fields(a: Dictionary, b: Dictionary) -> bool:
	## Development-only read-only schema comparison; no live tuning changes.
	for key in defaults():
		if not a.has(key) or not b.has(key) or a[key] != b[key]:
			return false
	return true
