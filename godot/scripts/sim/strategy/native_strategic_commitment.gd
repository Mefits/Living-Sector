extends RefCounted
## Frozen Rust: strategy/director.rs::retain_or_switch and accept_authorized_player_priority.
## Strategic choice only: never cancels native prepaid orders or creates contracts.
const DEFAULT_SUPERIORITY := 1.20
const DEFAULT_CONFIRMATIONS := 2

static func select(memory: Dictionary, offers: Array, tick: int, urgent_life_support: bool = false, native_plan_outstanding: bool = false, superiority: float = DEFAULT_SUPERIORITY, confirmations: int = DEFAULT_CONFIRMATIONS) -> Dictionary:
	var m: Dictionary = memory.duplicate(true)
	var valid: Array = []
	for offer in offers:
		if not (offer is Dictionary):
			continue
		var score: float = float(offer.get("score", 0.0))
		if offer.get("available", false) and is_finite(score) and score > 0.0:
			valid.append(offer)
	if valid.is_empty():
		return {"ok": false, "memory": m, "reason": "no_viable_candidates"}
	valid.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["score"]) != float(b["score"]):
			return float(a["score"]) > float(b["score"])
		if str(a.get("action", "")) != str(b.get("action", "")):
			return str(a.get("action", "")) < str(b.get("action", ""))
		return str(a.get("target", "")) < str(b.get("target", "")))
	var best: Dictionary = valid[0]
	var old: Dictionary = {}
	for offer in valid:
		if _same(offer, {"action": m.get("kind", ""), "target": m.get("target", null)}):
			old = offer
			break
	if old.is_empty():
		return _commit(m, best, tick, "previous_goal_unavailable")
	if _same(best, old):
		return _commit(m, old, tick, "viable_commitment_retained")
	if native_plan_outstanding and old.get("action") == "supply":
		return _commit(m, old, tick, "outstanding_native_plan_retained")
	if urgent_life_support and best.get("action") == "supply":
		return _commit(m, best, tick, "urgent_life_support")
	if float(best["score"]) < float(old["score"]) * superiority:
		return _commit(m, old, tick, "alternative_not_strong_enough")
	var pending: Dictionary = m.get("pending", {}) if m.get("pending") is Dictionary else {}
	var repeated: bool = _same(best, {"action": pending.get("kind"), "target": pending.get("target")})
	var cycles: int = mini(255, int(pending.get("consecutive_cycles", 0)) + 1) if repeated else 1
	if cycles >= confirmations:
		return _commit(m, best, tick, "sustained_higher_utility")
	m["pending"] = {"kind": best.get("action"), "target": best.get("target"), "consecutive_cycles": cycles, "first_seen_tick": pending.get("first_seen_tick", tick) if repeated else tick}
	m["score"] = old["score"]
	m["reason"] = "alternative_pending_confirmation"
	return {"ok": true, "memory": m, "candidate": old, "reason": "alternative_pending_confirmation"}

static func authorized_priority(memory: Dictionary, offer: Dictionary, tick: int) -> Dictionary:
	## Caller must first validate budget, charter, life support and native feasibility.
	return _commit(memory.duplicate(true), offer, tick, "player_delegated_priority")

static func _same(a: Dictionary, b: Dictionary) -> bool:
	return a.get("action") == b.get("action") and a.get("target") == b.get("target")

static func _commit(m: Dictionary, offer: Dictionary, tick: int, reason: String) -> Dictionary:
	if m.get("kind", "") != offer.get("action") or m.get("target") != offer.get("target"):
		m["since"] = tick
	m["kind"] = offer.get("action")
	m["target"] = offer.get("target")
	m["score"] = offer.get("score")
	m["reason"] = reason
	m["pending"] = null
	return {"ok": true, "memory": m, "candidate": offer, "reason": reason}
