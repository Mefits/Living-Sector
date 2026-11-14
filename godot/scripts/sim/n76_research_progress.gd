extends RefCounted
## Frozen Rust strategy/director.rs::research: +10 work per PAID shift,
## at most one paid shift per faction/tick; completion at progress >= required.
## A validated payment/stock/worker receipt is mandatory. Never mints technology.
const WORK_PER_SHIFT := 10

static func admit(commander: Dictionary, tick: int, receipt: Dictionary) -> Dictionary:
	if tick <= 0 or str(commander.get("research", "")).is_empty():
		return {"ok": false, "reason": "no_active_research"}
	if bool(commander.get("crisis", false)):
		return {"ok": false, "reason": "survival_first"}
	if int(commander.get("last_research_tick", -1)) >= tick:
		return {"ok": false, "reason": "already_researched"}
	var progress: int = int(commander.get("progress", -1))
	var required: int = int(commander.get("research_required", -1))
	if progress < 0 or required <= 0 or progress >= required:
		return {"ok": false, "reason": "invalid_progress"}
	if not bool(receipt.get("paid", false)) or not bool(receipt.get("electronics_debited", false)) or int(receipt.get("workers", 0)) != 10 or int(receipt.get("tick", -1)) != tick or str(receipt.get("faction_id", "")) != str(commander.get("faction_id", "")) or str(receipt.get("id", "")).is_empty():
		return {"ok": false, "reason": "unverified_paid_shift"}
	var next_progress: int = progress + WORK_PER_SHIFT
	return {"ok": true, "progress": next_progress, "completed": next_progress >= required, "technology": str(commander.research), "last_research_tick": tick, "receipt_id": str(receipt.id)}
