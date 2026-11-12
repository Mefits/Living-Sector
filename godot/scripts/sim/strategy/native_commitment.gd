extends RefCounted
## Rust strategy/director.rs retain_or_switch: strategic memory only.
## Never posts/cancels contracts, pays money, or changes world inventories.
const DEFAULT_SUPERIORITY := 1.20
const DEFAULT_CONFIRMATIONS := 2
var memory: Dictionary = {}

func _same(a: Dictionary, b: Dictionary) -> bool:
 return str(a.get("action","")) == str(b.get("action","")) and a.get("target",null) == b.get("target",null)

func _valid(a: Dictionary) -> bool:
 return bool(a.get("available",false)) and is_finite(float(a.get("score",0.0))) and float(a.get("score",0.0)) > 0.0

func _rank(a: Dictionary, b: Dictionary) -> bool:
 if float(a.score) != float(b.score): return float(a.score) > float(b.score)
 if str(a.action) != str(b.action): return str(a.action) < str(b.action)
 return str(a.get("target","")) < str(b.get("target",""))

func _commit(faction: String, choice: Dictionary, tick: int, reason: String) -> Dictionary:
 var previous: Dictionary = memory.get(faction,{})
 var since := int(previous.get("since",tick))
 if str(previous.get("kind","")) != str(choice.action) or previous.get("target",null) != choice.get("target",null):
  since = tick
 memory[faction] = {"kind":choice.action,"target":choice.get("target",null),
  "score":float(choice.score),"since":since,"reason":reason,"pending":{}}
 return {"choice":choice.duplicate(true),"reason":reason}

func choose(faction: String, offers: Array, tick: int, urgent_life_support: bool, native_plan_outstanding: bool, superiority: float = DEFAULT_SUPERIORITY, confirmations: int = DEFAULT_CONFIRMATIONS) -> Dictionary:
 if faction.is_empty() or tick < 0 or not is_finite(superiority) or superiority <= 0.0 or confirmations < 1: return {}
 var ranked: Array = []
 for offer in offers:
  if offer is Dictionary and _valid(offer) and offer.has("action"):
   ranked.append(offer)
 if ranked.is_empty(): return {}
 ranked.sort_custom(_rank)
 var best: Dictionary = ranked[0]
 var old_state: Dictionary = memory.get(faction,{})
 var incumbent: Dictionary = {}
 for candidate in ranked:
  if str(candidate.action) == str(old_state.get("kind","")) and candidate.get("target",null) == old_state.get("target",null):
   incumbent = candidate
   break
 if incumbent.is_empty(): return _commit(faction,best,tick,"previous_goal_unavailable")
 if _same(best,incumbent): return _commit(faction,incumbent,tick,"viable_commitment_retained")
 if native_plan_outstanding and incumbent.action == "supply":
  return _commit(faction,incumbent,tick,"outstanding_native_plan_retained")
 if urgent_life_support and best.action == "supply":
  return _commit(faction,best,tick,"urgent_life_support")
 if float(best.score) < float(incumbent.score) * superiority:
  return _commit(faction,incumbent,tick,"alternative_not_strong_enough")
 var pending: Dictionary = old_state.get("pending",{})
 var same_pending := pending.get("kind",null) == best.action and pending.get("target",null) == best.get("target",null)
 var cycles := int(pending.get("consecutive_cycles",0)) + 1 if same_pending else 1
 if cycles >= confirmations: return _commit(faction,best,tick,"sustained_higher_utility")
 var since := int(pending.get("first_seen_tick",tick)) if same_pending else tick
 old_state.pending = {"kind":best.action,"target":best.get("target",null),"consecutive_cycles":cycles,"first_seen_tick":since}
 old_state.score = float(incumbent.score)
 old_state.reason = "alternative_pending_confirmation"
 memory[faction] = old_state
 return {"choice":incumbent.duplicate(true),"reason":"alternative_pending_confirmation"}

func accept_player_priority(faction: String, offer: Dictionary, tick: int, authorized_and_funded: bool) -> Dictionary:
 if not authorized_and_funded or not _valid(offer) or faction.is_empty() or tick < 0: return {}
 return _commit(faction,offer,tick,"player_delegated_priority")

func snapshot() -> Dictionary:
 return memory.duplicate(true)

func restore(state: Dictionary) -> bool:
 for faction in state:
  if str(faction).is_empty() or not state[faction] is Dictionary: return false
  var record: Dictionary = state[faction]
  for key in ["kind","score","since","reason","pending"]:
   if not record.has(key): return false
  if not is_finite(float(record.score)) or int(record.since) < 0 or not record.pending is Dictionary: return false
 memory = state.duplicate(true)
 return true
