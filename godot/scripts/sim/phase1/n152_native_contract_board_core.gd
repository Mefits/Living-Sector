extends RefCounted
## N152 frozen sim_core/economy/contracts.rs ContractBoard structural owner.
## Immutable staged board (NOT a new wallet/escrow/ContractBoard instance).
## N104 owns real prepaid/settlement; N145 owns renewal/reputation aging.
## Native HashMap iteration order is unspecified: arrays preserve source
## insertion order when known, stable ID order only in admin snapshots.
const TYPES := ["delivery","construction","subsidy","passenger","crew_mission","courier","supply"]
const STATUSES := ["posted","accepted","picked_up","delivered","paid","expired"]
const MAX_I64: int = 9223372036854775807
const PROJECT_TAGS := ["strategy.logistics.v1","strategy.construction.v1","strategy.colony.v1"]

static func _fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func new_board() -> Dictionary:
	return {"next_id":0,"contracts":{},"by_status":{},
		"posted_by_destination":{},"posted_by_faction":{}}

static func _faction_key(faction: Variant) -> String:
	## String namespace avoids confusing Option None and a faction whose
	## literal name is "null" or the empty string.
	return JSON.stringify(["public"]) if faction == null else JSON.stringify(["faction",faction])

static func _array_add_unique(rows: Array, id: String) -> void:
	if not rows.has(id):
		rows.append(id)

static func _array_remove(rows: Array, id: String) -> void:
	while rows.has(id):
		rows.erase(id)

static func _add_status(board: Dictionary, id: String, status: String) -> void:
	var idx: Dictionary = board["by_status"]
	var rows: Array = idx.get(status,[])
	_array_add_unique(rows,id)
	idx[status] = rows

static func _remove_status(board: Dictionary, id: String, status: String) -> void:
	var idx: Dictionary = board["by_status"]
	if idx.has(status):
		_array_remove(idx[status],id)

static func _add_posted(board: Dictionary, id: String, c: Dictionary) -> void:
	var loc: String = str(c["destination_location"])
	var dest: Dictionary = board["posted_by_destination"]
	var loc_rows: Array = dest.get(loc,[])
	_array_add_unique(loc_rows,id)
	dest[loc] = loc_rows
	var key: String = _faction_key(c.get("faction_id",null))
	var tiers: Dictionary = board["posted_by_faction"].get(key,{})
	var tier: String = str(int(c["min_reputation"]))
	var ids: Array = tiers.get(tier,[])
	_array_add_unique(ids,id)
	tiers[tier] = ids
	board["posted_by_faction"][key] = tiers

static func _remove_posted(board: Dictionary, id: String, c: Dictionary) -> void:
	var loc: String = str(c["destination_location"])
	var dest: Dictionary = board["posted_by_destination"]
	if dest.has(loc):
		_array_remove(dest[loc],id)
	var key: String = _faction_key(c.get("faction_id",null))
	var by_faction: Dictionary = board["posted_by_faction"]
	if by_faction.has(key):
		var tiers: Dictionary = by_faction[key]
		var keys := tiers.keys()
		for tier in keys:
			_array_remove(tiers[tier],id)
			if tiers[tier].is_empty():
				tiers.erase(tier)
		# Rust retains the outer faction bucket when emptied.

static func _index_new(board: Dictionary, c: Dictionary) -> void:
	_add_status(board,str(c["id"]),str(c["status"]))
	if str(c["status"]) == "posted":
		_add_posted(board,str(c["id"]),c)

static func _move_status(board: Dictionary, id: String, old: String, next: String) -> void:
	_remove_status(board,id,old)
	_add_status(board,id,next)

static func _board_ok(board: Dictionary) -> bool:
	for key in ["next_id","contracts","by_status","posted_by_destination","posted_by_faction"]:
		if not board.has(key):
			return false
	return typeof(board["next_id"])==TYPE_INT and int(board["next_id"])>=0 and \
		board["contracts"] is Dictionary and board["by_status"] is Dictionary and \
		board["posted_by_destination"] is Dictionary and board["posted_by_faction"] is Dictionary

static func _valid_contract(c: Dictionary) -> bool:
	for key in ["id","contract_type","status","requestor_id","commodity","quantity",
			"source_location","destination_location","payment","initial_payment",
			"posted_at_tick","expires_at_tick","min_reputation","initial_min_reputation",
			"renewal_count"]:
		if not c.has(key):
			return false
	if not (c["id"] is String and not str(c["id"]).is_empty()
		and c["contract_type"] is String and str(c["contract_type"]) in TYPES
		and c["status"] is String and str(c["status"]) in STATUSES
		and c["requestor_id"] is String and c["commodity"] is String
		and c["source_location"] is String and c["destination_location"] is String):
		return false
	for key in ["quantity","payment","initial_payment","posted_at_tick","expires_at_tick",
			"min_reputation","initial_min_reputation","renewal_count"]:
		if typeof(c[key]) != TYPE_INT:
			return false
	if int(c["quantity"])<0 or int(c["posted_at_tick"])<0 or int(c["expires_at_tick"])<0 or \
			int(c["min_reputation"])<0 or int(c["min_reputation"])>100:
		return false
	if c.get("faction_id",null)!=null and not (c["faction_id"] is String):
		return false
	if c.get("fulfiller_id",null)!=null and not (c["fulfiller_id"] is String):
		return false
	if c.get("funding",null)!=null and not (c["funding"] is Dictionary):
		return false
	return true

static func fixed_strategy_reward(c: Dictionary) -> Variant:
	var funding = c.get("funding",null)
	if not (funding is Dictionary) or str(funding.get("source",""))!="faction":
		return null
	if str(c.get("mission_category","")) not in PROJECT_TAGS:
		return null
	return c["initial_payment"]

static func insert_loaded(board: Dictionary, original: Dictionary) -> Dictionary:
	## The source adds pre-built persisted contracts to all indices
	## and bumps next_id when id has contract-N suffix. It makes NO
	## funding transfer and keeps original post/accept timestamps.
	if not _board_ok(board) or not _valid_contract(original):
		return _fail("invalid_persisted_contract_or_board")
	var result := board.duplicate(true)
	var c := original.duplicate(true)
	var id: String = str(c["id"])
	if result["contracts"].has(id):
		return _fail("duplicate_loaded_id")
	var reward = fixed_strategy_reward(c)
	if c["status"]=="posted" and reward!=null:
		c["payment"] = reward
	if id.begins_with("contract-"):
		var suffix: String = id.substr(9)
		if suffix.is_valid_int():
			var n: int = int(suffix)
			if n>=0 and n<MAX_I64 and n>=int(result["next_id"]):
				result["next_id"]=n+1
	result["contracts"][id] = c
	_index_new(result,c)
	return {"ok":true,"board":result,"id":id}

static func post_kind(board: Dictionary, terms: Dictionary) -> Dictionary:
	## Owner must call N104 paid-funding apply separately and atomically
	## with this plan. This function ONLY posts the Board row like native
	## post_kind_with_faction; it never guesses a payer or puts up funds.
	if not _board_ok(board) or int(board["next_id"])>=MAX_I64:
		return _fail("invalid_board_or_contract_id_overflow")
	var kind: String = str(terms.get("contract_type",""))
	if kind not in TYPES:
		return _fail("invalid_contract_type")
	for k in ["requestor_id","commodity","source_location","destination_location",
			"quantity","payment","posted_at_tick","lifespan_ticks"]:
		if not terms.has(k):
			return _fail("missing_native_contract_term:"+k)
	for k in ["quantity","payment","posted_at_tick","lifespan_ticks"]:
		if typeof(terms[k])!=TYPE_INT:
			return _fail("invalid_native_contract_term:"+k)
	if int(terms["quantity"])<0 or int(terms["posted_at_tick"])<0 or int(terms["lifespan_ticks"])<0:
		return _fail("negative_contract_term")
	if int(terms["posted_at_tick"])>MAX_I64-int(terms["lifespan_ticks"]):
		return _fail("expiry_tick_overflow")
	var faction = terms.get("faction_id",null)
	if faction!=null and not (faction is String):
		return _fail("invalid_faction_id")
	var next := board.duplicate(true)
	var next_id: int = int(next["next_id"])+1
	var id: String = "contract-"+str(next_id)
	if next["contracts"].has(id):
		return _fail("contract_id_collision")
	var gate: int = 70 if kind=="subsidy" else (50 if kind=="crew_mission" else 0)
	var commodity: String = "food" if kind=="passenger" else ("tools" if kind=="crew_mission" else str(terms["commodity"]))
	var c := {"id":id,"contract_type":kind,"status":"posted",
		"requestor_id":terms["requestor_id"],"faction_id":faction,
		"fulfiller_id":null,"commodity":commodity,"quantity":terms["quantity"],
		"source_location":terms["source_location"],
		"destination_location":terms["destination_location"],
		"payment":terms["payment"],"initial_payment":terms["payment"],
		"funding":null,"posted_at_tick":terms["posted_at_tick"],
		"accepted_at_tick":null,
		"expires_at_tick":int(terms["posted_at_tick"])+int(terms["lifespan_ticks"]),
		"mission_category":terms.get("mission_category",null),
		"min_reputation":gate,"initial_min_reputation":gate,"renewal_count":0}
	if kind=="crew_mission":
		c["mission_category"] = terms.get("mission_category",null)
	if not _valid_contract(c):
		return _fail("invalid_posted_native_contract")
	next["next_id"]=next_id
	next["contracts"][id]=c
	_index_new(next,c)
	return {"ok":true,"board":next,"contract":c.duplicate(true),"id":id,
		"requires":"single_existing_N104_post_and_actual_payer_debit"}

static func count_by_status(board: Dictionary) -> Dictionary:
	var counts := {}
	if not _board_ok(board):
		return counts
	for status in board["by_status"]:
		counts[status]=board["by_status"][status].size()
	return counts

static func posted_for_destination(board: Dictionary, location: String) -> Array:
	## Original posted_by_destination vector, with stale non-posted
	## entries always filtered out at view time.
	var out: Array = []
	if not _board_ok(board):
		return out
	for id in board["posted_by_destination"].get(location,[]):
		if board["contracts"].has(id) and board["contracts"][id]["status"]=="posted":
			out.append(board["contracts"][id].duplicate(true))
	return out

static func posted_for_ship(board: Dictionary, faction_reputation: Dictionary) -> Array:
	## Existing N145 ages and re-buckets; this source-index adapter
	## consumes exactly the UPDATED tier indices, with rep0 strangers.
	var out: Array = []
	if not _board_ok(board):
		return out
	for key in board["posted_by_faction"]:
		var decoded: Variant = JSON.parse_string(str(key))
		if not (decoded is Array) or decoded.size()==0:
			continue
		var rep: int = 0
		if decoded.size()>=2 and str(decoded[0])=="faction":
			rep=int(faction_reputation.get(str(decoded[1]),0))
		var tiers: Dictionary = board["posted_by_faction"][key]
		var ranks := tiers.keys()
		ranks.sort_custom(func(a,b): return int(a)<int(b))
		for rank in ranks:
			if int(rank)>rep:
				continue
			for id in tiers[rank]:
				if board["contracts"].has(id) and board["contracts"][id]["status"]=="posted":
					out.append(board["contracts"][id].duplicate(true))
	return out

static func check_indices(board: Dictionary) -> Dictionary:
	## Stronger-than-source integrity preflight: tests that a hydratable
	## board contains each contract ONCE in its appropriate indices.
	## Used only by debugger / native engine before applying changes.
	if not _board_ok(board):
		return _fail("invalid_board")
	var mismatches: Array[String] = []
	for id in board["contracts"]:
		var c: Dictionary = board["contracts"][id]
		if not _valid_contract(c):
			mismatches.append("invalid_contract:"+str(id))
			continue
		var status: String = str(c["status"])
		if board["by_status"].get(status,[]).count(id)!=1:
			mismatches.append("status_index:"+str(id))
		if status=="posted":
			if board["posted_by_destination"].get(c["destination_location"],[]).count(id)!=1:
				mismatches.append("destination_index:"+str(id))
			var fac_key: String = _faction_key(c.get("faction_id",null))
			var tiers: Dictionary = board["posted_by_faction"].get(fac_key,{})
			if tiers.get(str(int(c["min_reputation"])),[]).count(id)!=1:
				mismatches.append("faction_index:"+str(id))
	for status in board["by_status"]:
		for id in board["by_status"][status]:
			if not board["contracts"].has(id) or board["contracts"][id]["status"]!=status:
				mismatches.append("stale_status:"+str(id))
	for loc in board["posted_by_destination"]:
		for id in board["posted_by_destination"][loc]:
			if not board["contracts"].has(id) or board["contracts"][id]["status"]!="posted" or \
					board["contracts"][id]["destination_location"]!=loc:
				mismatches.append("stale_destination:"+str(id))
	for key in board["posted_by_faction"]:
		for tier in board["posted_by_faction"][key]:
			for id in board["posted_by_faction"][key][tier]:
				if not board["contracts"].has(id):
					mismatches.append("missing_tier_id:"+str(id))
					continue
				var c: Dictionary = board["contracts"][id]
				if c["status"]!="posted" or _faction_key(c.get("faction_id",null))!=key or \
						str(int(c["min_reputation"]))!=str(tier):
					mismatches.append("stale_faction_tier:"+str(id))
	return {"ok":mismatches.is_empty(),"errors":mismatches}
