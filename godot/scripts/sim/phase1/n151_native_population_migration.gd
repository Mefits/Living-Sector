extends RefCounted
## N151 last parity edge in native population.rs::run_population_migration.
## Supersedes N114 on Phase2 world owner where exact integral wealth
## conservation matters. Pure projected population movement, no
## passengers/contracts/teleport: this is the ORIGINAL abstract pop
## migration function, not new physical N147 colony passenger logistics.
const TRIGGER: float = 1.0
const HEAD_COUNT: int = 100
const MIN_DEST_SENTIMENT: int = 50
const MAX_I64: int = 9223372036854775807
const MIN_I64: int = -9223372036854775807 - 1

static func _fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func migrate(populations: Array, tick: int) -> Dictionary:
	## Exact native iteration order is the ECS query order supplied
	## by the exclusive world adapter. Rust max_by prefers the last
	## equivalent candidate, so >= updates the selected index.
	if tick<0:
		return _fail("invalid_tick")
	var next: Array = populations.duplicate(true)
	var source_index: int = -1
	var pressure: float = -1.0
	for i in range(next.size()):
		var p = next[i]
		if not (p is Dictionary) or not (p.get("id") is String) or 				typeof(p.get("population_count"))!=TYPE_INT or 				not (typeof(p.get("migration_pressure")) in [TYPE_FLOAT,TYPE_INT]) or 				not is_finite(float(p.get("migration_pressure"))):
			return _fail("invalid_native_population")
		if bool(p.get("is_dock",false)) or int(p["population_count"])<=300:
			continue
		var value: float = float(p["migration_pressure"])
		if value>=TRIGGER and value>=pressure:
			source_index=i
			pressure=value
	if source_index<0:
		return {"ok":true,"populations":next,"moved":0,"events":[]}
	var src: Dictionary = next[source_index]
	var destination_index: int = -1
	var best_sent: int = -2147483648
	for i in range(next.size()):
		if i==source_index:
			continue
		var p: Dictionary = next[i]
		if bool(p.get("is_dock",false)) or 				str(p.get("facility_location",""))==str(src.get("facility_location","")):
			continue
		var sent: int = int(p.get("overall_sentiment",0))
		if sent>=MIN_DEST_SENTIMENT and sent>=best_sent:
			best_sent=sent
			destination_index=i
	if destination_index<0:
		return {"ok":true,"populations":next,"moved":0,"events":[]}
	var dest: Dictionary = next[destination_index]
	var source_count: int = int(src["population_count"])
	var moved: int = mini(HEAD_COUNT,maxi(0,source_count-100))
	if moved<=0:
		return {"ok":true,"populations":next,"moved":0,"events":[]}
	if typeof(src.get("total_wealth"))!=TYPE_INT or typeof(dest.get("total_wealth"))!=TYPE_INT:
		return _fail("missing_native_population_economy")
	var source_money: int = int(src["total_wealth"])
	var dest_money: int = int(dest["total_wealth"])
	if source_money<0:
		return {"ok":true,"populations":next,"moved":0,"events":[]}
	# Rust computes (source_cash as i128 * moved as i128 / heads)
	# exactly. Split integer quotient/remainder to avoid i64 overflow
	# during multiplication for almost all real worlds.
	var quotient: int = int(source_money/source_count)
	var remainder: int = source_money%source_count
	if remainder>MAX_I64/moved:
		return _fail("native_i128_proportional_transfer_required")
	var payment: int = quotient*moved+int((remainder*moved)/source_count)
	if payment<0 or dest_money>MAX_I64-payment:
		return {"ok":true,"populations":next,"moved":0,"events":[]}
	# destination may have NEGATIVE wealth: original only forbids
	# negative source wealth and checks dest.checked_add(payment).
	src["total_wealth"]=source_money-payment
	dest["total_wealth"]=dest_money+payment
	src["population_count"]=source_count-moved
	dest["population_count"]=mini(MAX_I64,int(dest["population_count"])+moved)
	src["migration_pressure"]=0.0
	src["sentiment_dirty"]=true
	dest["sentiment_dirty"]=true
	next[source_index]=src
	next[destination_index]=dest
	var event := {"kind":"population_migrated",
		"source_id":src["id"],"source_label":src.get("label",""),
		"source_location":src.get("facility_location",""),
		"destination_id":dest["id"],"destination_label":dest.get("label",""),
		"destination_location":dest.get("facility_location",""),
		"count":moved,"source_sentiment":int(src.get("overall_sentiment",0)),
		"destination_sentiment":int(dest.get("overall_sentiment",0))}
	return {"ok":true,"populations":next,"moved":moved,
		"wealth_transferred":payment,"events":[event],
		"authority":"one_native_world_migration_transaction"}
