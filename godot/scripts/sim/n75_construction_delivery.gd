extends RefCounted
## Frozen Rust: agents/construction.rs: material required=600, labor required=150.
## This is an admission receipt only; no goods are materialized or debited here.
const MATERIAL_REQUIRED := 600
const LABOR_REQUIRED := 150

static func delivery(site: Dictionary, commodity: String, location: String, quantity: int, receipt_id: String, seen: Dictionary) -> Dictionary:
	if receipt_id.is_empty() or seen.has(receipt_id):
		return {"ok": false, "reason": "duplicate_or_missing_receipt"}
	if quantity <= 0 or commodity.is_empty() or location.is_empty():
		return {"ok": false, "reason": "invalid_delivery"}
	if bool(site.get("completed", false)):
		return {"ok": false, "reason": "already_completed"}
	if str(site.get("commodity", "")) != commodity or str(site.get("location", "")) != location:
		return {"ok": false, "reason": "wrong_site"}
	var delivered: int = int(site.get("progress_delivered", -1))
	var required: int = int(site.get("progress_required", MATERIAL_REQUIRED))
	if required <= 0 or delivered < 0 or delivered > required or quantity > required - delivered:
		return {"ok": false, "reason": "exceeds_material_requirement"}
	return {"ok": true, "receipt_id": receipt_id, "new_delivered": delivered + quantity, "remaining": required - delivered - quantity}

static func completion_ready(site: Dictionary) -> bool:
	var required: int = int(site.get("progress_required", MATERIAL_REQUIRED))
	var labor: Dictionary = site.get("labor", {})
	return not bool(site.get("completed", false)) and required > 0 and int(site.get("progress_delivered", -1)) >= required and int(labor.get("required", LABOR_REQUIRED)) > 0 and int(labor.get("completed", -1)) >= int(labor.get("required", LABOR_REQUIRED))
