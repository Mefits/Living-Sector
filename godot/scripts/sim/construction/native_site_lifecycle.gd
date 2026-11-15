extends RefCounted
## Rust agents/construction.rs: site material and labor are separate durable counters.
## This model does not debit stock, pay wages or spawn a facility. Callers must
## present authenticated delivery/paid-work receipts and commit their ledgers first.
const MATERIAL_REQUIRED := 600
const LABOR_REQUIRED := 150
const PRODUCERS := {
 "ore":"mining_rig","ice":"mining_rig","gas":"mining_rig",
 "rare_ore":"mining_rig","crystal_ore":"mining_rig",
 "metals":"refinery","water":"refinery","polymers":"refinery","fuel":"refinery",
 "alloys":"alloyplant2","quantum_cores":"qfab3",
 "components":"factory","electronics":"factory","tools":"factory",
 "luxury":"factory","medical":"factory","food":"farm"
}
var sites: Dictionary = {}

func create_site(id: String, faction: String, body: String, location: String, commodity: String, tick: int, required: int = MATERIAL_REQUIRED) -> bool:
 if id.is_empty() or faction.is_empty() or body.is_empty() or location.is_empty() or not PRODUCERS.has(commodity) or required <= 0 or tick < 0 or sites.has(id):
  return false
 for site in sites.values():
  if site.location == location and site.commodity == commodity and not site.completed:
   return false
 sites[id] = {"id":id,"faction":faction,"body":body,"location":location,"commodity":commodity,
  "facility_type":PRODUCERS[commodity],"spawned_at_tick":tick,"required":required,
  "delivered":0,"labor_required":LABOR_REQUIRED,"labor_completed":0,"completed":false,
  "delivery_receipts":{},"labor_receipts":{},"dirty":true}
 return true

func remaining(id: String) -> int:
 if not sites.has(id): return -1
 var s: Dictionary = sites[id]
 return maxi(0, int(s.required) - int(s.delivered))

func material_fraction(id: String) -> float:
 if not sites.has(id): return 0.0
 var s: Dictionary = sites[id]
 return clampf(float(s.delivered) / float(s.required), 0.0, 1.0)

func admit_delivery(id: String, receipt: String, location: String, commodity: String, quantity: int, externally_committed: bool) -> bool:
 if not externally_committed or receipt.is_empty() or quantity <= 0 or not sites.has(id): return false
 var s: Dictionary = sites[id]
 if s.completed or s.location != location or s.commodity != commodity or s.delivery_receipts.has(receipt): return false
 if quantity > remaining(id): return false
 s.delivered += quantity
 s.delivery_receipts[receipt] = quantity
 s.dirty = true
 return true

func admit_paid_labor(id: String, receipt: String, shifts: int, externally_paid: bool) -> bool:
 if not externally_paid or receipt.is_empty() or shifts <= 0 or not sites.has(id): return false
 var s: Dictionary = sites[id]
 if s.completed or s.delivered < s.required or s.labor_receipts.has(receipt): return false
 if shifts > int(s.labor_required) - int(s.labor_completed): return false
 s.labor_completed += shifts
 s.labor_receipts[receipt] = shifts
 s.dirty = true
 return true

func ready_to_materialize(id: String) -> bool:
 if not sites.has(id): return false
 var s: Dictionary = sites[id]
 return not s.completed and s.delivered >= s.required and s.labor_completed >= s.labor_required

func acknowledge_materialization(id: String, committed_facility_id: String) -> bool:
 if committed_facility_id.is_empty() or not ready_to_materialize(id): return false
 sites[id].completed = true
 sites[id].dirty = true
 return true

func snapshot() -> Dictionary:
 return sites.duplicate(true)

func restore(candidate: Dictionary) -> bool:
 var seen: Dictionary = {}
 for id in candidate:
  if not candidate[id] is Dictionary: return false
  var s: Dictionary = candidate[id]
  for key in ["id","faction","body","location","commodity","facility_type","required","delivered","labor_required","labor_completed","completed","delivery_receipts","labor_receipts"]:
   if not s.has(key): return false
  if s.id != id or not PRODUCERS.has(s.commodity) or s.facility_type != PRODUCERS[s.commodity]: return false
  if int(s.required) <= 0 or int(s.delivered) < 0 or int(s.delivered) > int(s.required): return false
  if int(s.labor_required) <= 0 or int(s.labor_completed) < 0 or int(s.labor_completed) > int(s.labor_required): return false
  if s.completed and (s.delivered < s.required or s.labor_completed < s.labor_required): return false
  var key := str(s.location) + "|" + str(s.commodity)
  if not s.completed and seen.has(key): return false
  seen[key] = true
 sites = candidate.duplicate(true)
 return true
