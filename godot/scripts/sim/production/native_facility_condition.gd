extends RefCounted
## CODE_UNVERIFIED. Rust agents/facility/mod.rs condition/repair/abandonment.
## Repairs require caller-confirmed workforce admission; no credits created here.
const DEGRADE := 0.0002
const REPAIR_THRESHOLD := 0.8
const REPAIR_PER_TOOL := 0.01
const REPAIR_INTERVAL := 20
const ABANDON_INTERVAL := 10
const ABANDON_AFTER := 200
var _facilities: Dictionary = {}
var _repair_receipts: Dictionary = {}

func import_facilities(states: Dictionary) -> bool:
	if not _facilities.is_empty() or states.is_empty():
		return false
	for id in states:
		if typeof(id) != TYPE_STRING or id.is_empty() or not _valid_state(states[id]):
			return false
	_facilities = states.duplicate(true)
	return true

## Only consecutive ticks admitted. Native phase order: degrade, repair, abandon.
## paid_repair_ids are authorization receipts from real workforce/payroll, not promises.
func step(tick: int, tick_scale: float, multiplier: int, paid_repair_ids: Dictionary) -> Dictionary:
	if tick < 0 or multiplier < 1 or not is_finite(tick_scale) or tick_scale < 0.0:
		return {"ok": false, "reason": "invalid_tick"}
	var next := _facilities.duplicate(true)
	var events: Array = []
	var next_receipts := _repair_receipts.duplicate(true)
	var ids := next.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = next[id]
		if not _valid_state(s) or tick != int(s["last_tick"]) + 1:
			return {"ok": false, "reason": "replayed_or_skipped_tick"}
		if not s["abandoned"]:
			s["condition"] = maxf(0.0, float(s["condition"]) - DEGRADE * tick_scale)
			if tick % (REPAIR_INTERVAL * multiplier) == 0 and s["condition"] < REPAIR_THRESHOLD and s["tools"] >= 1.0 and paid_repair_ids.has(id):
				if typeof(paid_repair_ids[id]) != TYPE_STRING or str(paid_repair_ids[id]).is_empty() or next_receipts.has(paid_repair_ids[id]):
					return {"ok": false, "reason": "invalid_payroll_receipt"}
				next_receipts[paid_repair_ids[id]] = {"facility": id, "tick": tick}
				s["tools"] -= 1.0
				s["condition"] = minf(1.0, float(s["condition"]) + REPAIR_PER_TOOL)
			if tick % (ABANDON_INTERVAL * multiplier) == 0:
				var dying: bool = s["condition"] < 0.1 and s["tools"] < 1.0 and s["credits"] < 100
				if dying:
					s["abandon_counter"] += 1
					if s["abandon_counter"] >= ABANDON_AFTER:
						s["abandoned"] = true
						events.append({"kind": "facility_abandoned", "facility_id": id})
				else:
					s["abandon_counter"] = 0
		s["last_tick"] = tick
	_facilities = next
	_repair_receipts = next_receipts
	return {"ok": true, "events": events}

func facility(id: String) -> Dictionary:
	return _facilities.get(id, {}).duplicate(true)

func snapshot() -> Dictionary:
	return {"version": 1, "facilities": _facilities.duplicate(true), "repair_receipts": _repair_receipts.duplicate(true)}

func restore(data: Dictionary) -> bool:
	if data.get("version") != 1 or typeof(data.get("facilities")) != TYPE_DICTIONARY or data["facilities"].is_empty() or typeof(data.get("repair_receipts")) != TYPE_DICTIONARY:
		return false
	for id in data["facilities"]:
		if typeof(id) != TYPE_STRING or id.is_empty() or not _valid_state(data["facilities"][id]):
			return false
	for receipt in data["repair_receipts"]:
		if typeof(receipt) != TYPE_STRING or receipt.is_empty() or typeof(data["repair_receipts"][receipt]) != TYPE_DICTIONARY:
			return false
	_facilities = data["facilities"].duplicate(true)
	_repair_receipts = data["repair_receipts"].duplicate(true)
	return true

func _valid_state(s: Variant) -> bool:
	if typeof(s) != TYPE_DICTIONARY:
		return false
	for key in ["condition", "tools", "credits", "abandon_counter", "abandoned", "last_tick"]:
		if not s.has(key):
			return false
	if typeof(s["abandoned"]) != TYPE_BOOL or typeof(s["abandon_counter"]) != TYPE_INT or typeof(s["last_tick"]) != TYPE_INT or typeof(s["credits"]) != TYPE_INT:
		return false
	if s["abandon_counter"] < 0 or s["last_tick"] < -1 or s["credits"] < 0:
		return false
	var condition: float = float(s["condition"])
	var tools: float = float(s["tools"])
	return is_finite(condition) and condition >= 0.0 and condition <= 1.0 and is_finite(tools) and tools >= 0.0
