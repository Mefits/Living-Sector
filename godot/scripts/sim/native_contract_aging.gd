extends RefCounted
## N145. Frozen Rust contracts.rs: Posted aging, reputation admission, renewal and expiry.
## Input: {contract_id: Dictionary} with native Contract serialized fields.
## This is a board-domain state transition, NOT a financial ledger.
## Call on an exclusive board snapshot; persist returned contracts atomically with the
## authoritative board indexes. Expired escrow refunds belong to N104, never here.
const REP_INTERVAL: int = 100
const REP_STEP: int = 10
const PAYMENT_INTERVAL: int = 50
const PAYMENT_STEP_PCT: int = 5
const PAYMENT_CAP_PCT: int = 100
const MAX_RENEWALS: int = 3
const RENEW_REP_DROP: int = 15
const DEFAULT_LIFESPAN: int = 300
const MAX_I64: int = 9223372036854775807

static func _posted(c: Dictionary) -> bool:
	return str(c.get("status", "")).to_lower() == "posted"

static func _type(c: Dictionary) -> String:
	return str(c.get("contract_type", "")).to_lower()

static func _fixed_reward(c: Dictionary) -> bool:
	var funding: Dictionary = c.get("funding", {}) if c.get("funding", {}) is Dictionary else {}
	var category := str(c.get("mission_category", ""))
	return str(funding.get("source", "")).to_lower() == "faction" and category in ["strategy.logistics.v1", "strategy.construction.v1", "strategy.colony.v1"]

static func _age(tick: int, posted: int) -> int:
	return maxi(0, tick - posted)

static func _u8_saturating_mul(a: int, b: int) -> int:
	return mini(255, a * b)

static func _safe_payment(base: int, pct: int) -> int:
	if base < 0 or base > MAX_I64 / (100 + pct):
		return -1
	return base + int((base * pct) / 100)

static func age_open_reputation(contracts: Dictionary, tick: int) -> Dictionary:
	var next := contracts.duplicate(true)
	for id in next.keys():
		var c: Dictionary = next[id]
		if not _posted(c):
			continue
		var old_rep := int(c.get("min_reputation", 0))
		if old_rep <= 0:
			continue
		var age := _age(tick, int(c.get("posted_at_tick", 0)))
		if age == 0:
			continue
		# Rust casts steps to u8 before saturating multiplication.
		var steps_u8 := int(age / REP_INTERVAL) % 256
		var original := int(c.get("initial_min_reputation", 0))
		var expected := maxi(0, original - _u8_saturating_mul(steps_u8, REP_STEP))
		c["min_reputation"] = mini(old_rep, expected)
		next[id] = c
	return next

static func age_escalate_payment(contracts: Dictionary, tick: int) -> Dictionary:
	var next := contracts.duplicate(true)
	for id in next.keys():
		var c: Dictionary = next[id]
		if not _posted(c):
			continue
		if _fixed_reward(c):
			c["payment"] = int(c.get("initial_payment", 0))
			next[id] = c
			continue
		var initial := int(c.get("initial_payment", 0))
		if initial <= 0:
			continue
		var steps := int(_age(tick, int(c.get("posted_at_tick", 0))) / PAYMENT_INTERVAL)
		var pct := mini(PAYMENT_CAP_PCT, steps * PAYMENT_STEP_PCT)
		var bumped := _safe_payment(initial, pct)
		if bumped >= 0:
			c["payment"] = maxi(int(c.get("payment", 0)), bumped)
			next[id] = c
	return next

static func sweep_expiring(contracts: Dictionary, tick: int, lifespan: int = DEFAULT_LIFESPAN) -> Dictionary:
	# Returns {ok, contracts, renewed, expired}. No funds/cargo are touched.
	if lifespan < 0 or tick < 0:
		return {"ok": false, "error": "invalid_tick_or_lifespan"}
	var next := contracts.duplicate(true)
	var renewed: Array = []
	var expired: Array = []
	var ids: Array = next.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = next[id]
		if not _posted(c) or tick < int(c.get("expires_at_tick", MAX_I64)):
			continue
		var kind := _type(c)
		var count := int(c.get("renewal_count", 0))
		var subsidy := kind == "subsidy"
		var can_renew := (kind in ["delivery", "construction"] and count < MAX_RENEWALS) or (subsidy and count < 1)
		if can_renew:
			if tick > MAX_I64 - lifespan:
				return {"ok": false, "error": "expiry_overflow"}
			var current_payment := int(c.get("payment", 0))
			if _fixed_reward(c):
				c["payment"] = int(c.get("initial_payment", 0))
			else:
				# Rust: (payment as f32 * 1.25).round() as i64.
				# float32 rounding and saturating cast need Godot runtime parity check.
				var payment_float := float(current_payment) * 1.25
				c["payment"] = mini(MAX_I64, maxi(0, int(floor(payment_float + 0.5))))
			c["min_reputation"] = 0 if subsidy else maxi(0, int(c.get("min_reputation", 0)) - RENEW_REP_DROP)
			c["expires_at_tick"] = tick + lifespan
			c["renewal_count"] = mini(255, count + 1)
			next[id] = c
			renewed.append({"id": str(id), "commodity": c.get("commodity"), "destination": c.get("destination_location"), "new_payment": c["payment"], "new_min_rep": c["min_reputation"], "renewal_count": c["renewal_count"]})
		else:
			c["status"] = "expired"
			next[id] = c
			expired.append({"id": str(id), "commodity": c.get("commodity"), "destination": c.get("destination_location"), "contract_type": kind, "final_payment": c.get("payment", 0)})
	return {"ok": true, "contracts": next, "renewed": renewed, "expired": expired}

static func posted_indexes(contracts: Dictionary) -> Dictionary:
	# Rebuild the native by_status, posted_by_destination and posted_by_faction tiers.
	# Key "" denotes None faction, distinct from a real faction ID.
	var status: Dictionary = {}
	var destination: Dictionary = {}
	var faction: Dictionary = {}
	var ids: Array = contracts.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = contracts[id]
		var state := str(c.get("status", "")).to_lower()
		if not status.has(state):
			status[state] = []
		status[state].append(id)
		if not _posted(c):
			continue
		var dest := str(c.get("destination_location", ""))
		if not destination.has(dest):
			destination[dest] = []
		destination[dest].append(id)
		var fac := str(c.get("faction_id", ""))
		var tier := int(c.get("min_reputation", 0))
		if not faction.has(fac):
			faction[fac] = {}
		if not faction[fac].has(tier):
			faction[fac][tier] = []
		faction[fac][tier].append(id)
	return {"by_status": status, "posted_by_destination": destination, "posted_by_faction": faction}

static func posted_for_ship(contracts: Dictionary, reputation: Dictionary) -> Array:
	var index := posted_indexes(contracts)["posted_by_faction"]
	var selected: Array = []
	for faction in index.keys():
		var ship_rep := 0 if faction == "" else int(reputation.get(faction, 0))
		for tier in index[faction].keys():
			if int(tier) <= ship_rep:
				selected.append_array(index[faction][tier])
	selected.sort()
	return selected

static func advance_posted(contracts: Dictionary, tick: int, lifespan: int) -> Dictionary:
	# Rust callers run reputation, price aging, then expiry on the board.
	var aged := age_escalate_payment(age_open_reputation(contracts, tick), tick)
	return sweep_expiring(aged, tick, lifespan)
