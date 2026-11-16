extends RefCounted
## CODE_UNVERIFIED — data-only accounting boundary; not a second money supply.
## Rust reference: economy/money.rs, agents/facility/workforce.rs.
## Amounts are integer credits (i64 in Rust). Do not convert market f32 prices here.
const MAX_CREDITS: int = 9223372036854775807

var _balances: Dictionary = {}

## Persistent append-only receipt index, split into bounded deterministic
## hash partitions. Forks share OLD immutable partitions and order chunks,
## cloning only an outer index header. Writing one new receipt detaches the
## affected partition and the final at-most-64-ID order chunk, preserving
## all previous snapshots and the original insertion order on N38 export.
## No receipt data is shared with untrusted caller dictionaries.
const RECEIPT_PARTITIONS: int = 256
const ORDER_CHUNK_SIZE: int = 64
var _receipt_partitions: Array = []
var _receipt_order_chunks: Array = []
var _receipt_count: int = 0
## Exact per-kind counts, updated only on committed append or validated restore.
## A fork owns its counter dictionary: never mutate the parent's counters.
var _receipt_kind_counts: Dictionary = {}
## Only trusted private receipt records live in this flattened read cache.
## It is NEVER exposed to callers; snapshot() returns a detached deep copy.
## The flattened map is rebuilt once per changed receipt generation, and
## otherwise reused across repeated N39 proofs/saves (many per tick).
var _flat_receipt_cache: Dictionary = {}
var _flat_cache_count: int = -1

func _init() -> void:
	_receipt_partitions.resize(RECEIPT_PARTITIONS)
	for i in range(RECEIPT_PARTITIONS):
		_receipt_partitions[i] = {}

func _bucket_index(id: String) -> int:
	return int(id.hash()) & (RECEIPT_PARTITIONS - 1)

func _has_receipt_id(id: String) -> bool:
	return (_receipt_partitions[_bucket_index(id)] as Dictionary).has(id)

func _receipt_at(id: String) -> Dictionary:
	return (_receipt_partitions[_bucket_index(id)] as Dictionary).get(id, {})

func _append_receipt(id: String, record: Dictionary) -> void:
	# Strictly new immutable record. Every existing shard and order chunk
	# is treated read-only across independent owned Ledger forks.
	var bucket: int = _bucket_index(id)
	var detached: Dictionary = (
		_receipt_partitions[bucket] as Dictionary).duplicate()
	detached[id] = record.duplicate(true)
	_receipt_partitions[bucket] = detached
	var last: int = _receipt_order_chunks.size() - 1
	if last < 0 or (_receipt_order_chunks[last] as Array).size() >= ORDER_CHUNK_SIZE:
		_receipt_order_chunks.append([id])
	else:
		var order: Array = (_receipt_order_chunks[last] as Array).duplicate()
		order.append(id)
		_receipt_order_chunks[last] = order
	_receipt_count += 1
	var kind: Variant = record.get("kind", null)
	if kind is String:
		_receipt_kind_counts[kind] = int(_receipt_kind_counts.get(kind, 0)) + 1
	# Rebuilding is delayed until a real full N38/provenance snapshot.
	# A fork that still sees older immutable shards retains its own cache.
	_flat_receipt_cache = {}
	_flat_cache_count = -1

func _snapshot_receipts() -> Dictionary:
	if _flat_cache_count != _receipt_count:
		var ordered: Dictionary = {}
		for chunk in _receipt_order_chunks:
			for id in chunk:
				# Private original rows never escape this cache. No per-row
				# deep duplication in GDScript: one native deep copy below.
				ordered[id] = _receipt_at(str(id))
		_flat_receipt_cache = ordered
		_flat_cache_count = _receipt_count
	return _flat_receipt_cache.duplicate(true)

func import_accounts(accounts: Dictionary) -> bool:
	if not _balances.is_empty() or _receipt_count != 0:
		return false
	for account in accounts:
		if not _valid_account(account) or not _valid_amount(accounts[account]):
			return false
	_balances = accounts.duplicate(true)
	return true

## Register a previously unknown escrow wallet at ZERO only. This is the same
## authoritative N9 ledger: it cannot create credits or replace an existing
## account. The caller must stage/validate the entire contract transaction
## before publishing this ledger snapshot to the canonical World Apply.
func register_empty_account(account: String) -> bool:
	if not _valid_account(account) or _balances.has(account):
		return false
	_balances[account] = 0
	return true

func balance(account: String) -> int:
	return int(_balances.get(account, -1))

func total() -> int:
	var result: int = 0
	for account in _balances:
		result += int(_balances[account])
	return result

func has_receipt(operation_id: String) -> bool:
	return _has_receipt_id(operation_id)

## All legs are committed together; sum must be zero. Duplicate IDs never reapply.
## legs: [{account: String, delta: int}]. Negative delta is a debit.
func commit(operation_id: String, legs: Array, tick: int, kind: String) -> Dictionary:
	if operation_id.is_empty() or tick < 0 or kind.is_empty():
		return {"ok": false, "reason": "invalid_operation"}
	if _has_receipt_id(operation_id):
		return {"ok": false, "reason": "duplicate_operation"}
	if legs.size() < 2:
		return {"ok": false, "reason": "missing_counterparty"}
	var changes: Dictionary = {}
	var debits: int = 0
	var credits: int = 0
	for leg in legs:
		if not (leg is Dictionary) or not leg.has("account") or not leg.has("delta"):
			return {"ok": false, "reason": "invalid_leg"}
		var account = leg["account"]
		var delta = leg["delta"]
		if not _valid_account(account) or not _balances.has(account) or typeof(delta) != TYPE_INT:
			return {"ok": false, "reason": "invalid_account_or_delta"}
		if delta == -9223372036854775807 - 1:
			return {"ok": false, "reason": "integer_overflow"}
		if delta < 0:
			if debits > MAX_CREDITS + delta:
				return {"ok": false, "reason": "integer_overflow"}
			debits -= delta
		else:
			if credits > MAX_CREDITS - delta:
				return {"ok": false, "reason": "integer_overflow"}
			credits += delta
		var old_change: int = int(changes.get(account, 0))
		if delta > 0 and old_change > MAX_CREDITS - delta:
			return {"ok": false, "reason": "integer_overflow"}
		if delta < 0 and old_change < -MAX_CREDITS - delta:
			return {"ok": false, "reason": "integer_overflow"}
		changes[account] = old_change + delta
	if debits == 0 or debits != credits:
		return {"ok": false, "reason": "unbalanced"}
	for account in changes:
		var before: int = int(_balances[account])
		var change: int = int(changes[account])
		if change < 0 and before < -change:
			return {"ok": false, "reason": "insufficient_funds"}
		if change > 0 and before > MAX_CREDITS - change:
			return {"ok": false, "reason": "integer_overflow"}
	for account in changes:
		_balances[account] = int(_balances[account]) + int(changes[account])
	var receipt = {"id": operation_id, "tick": tick, "kind": kind, "legs": legs.duplicate(true)}
	_append_receipt(operation_id, receipt)
	return {"ok": true, "receipt": receipt.duplicate(true)}

func transfer(operation_id: String, source: String, destination: String, amount: int, tick: int, kind: String) -> Dictionary:
	if source == destination or amount <= 0:
		return {"ok": false, "reason": "invalid_transfer"}
	return commit(operation_id, [{"account": source, "delta": -amount}, {"account": destination, "delta": amount}], tick, kind)

## A frozen Rust admin despawn physically destroys the actor and its
## remaining personal/facility credits. It is NOT a treasury transfer.
## Keep an explicit immutable N9 write-off receipt and remove the wallet;
## total credits fall by exactly the erased actor's old credits. This
## privileged operation is used ONLY by the N39 atomic admin cascade.
func close_removed_entity_account(operation_id: String,
		account: String, tick: int, kind: String) -> Dictionary:
	if operation_id.is_empty() or not _valid_account(account) or tick < 0:
		return {"ok": false, "reason": "invalid_admin_account_removal"}
	if kind not in ["ship_decommissioned", "facility_removed"]:
		return {"ok": false, "reason": "invalid_admin_writeoff_kind"}
	if not _balances.has(account) or _has_receipt_id(operation_id):
		return {"ok": false, "reason": "account_missing_or_previously_removed"}
	if kind == "ship_decommissioned" and not account.begins_with("ship:"):
		return {"ok": false, "reason": "not_a_ship_wallet"}
	if kind == "facility_removed" and not account.begins_with("facility/"):
		return {"ok": false, "reason": "not_a_facility_wallet"}
	var lost: int = int(_balances[account])
	if lost < 0:
		return {"ok": false, "reason": "invalid_decommission_balance"}
	_balances.erase(account)
	var record: Dictionary = {"id": operation_id, "tick": tick,
		"kind": kind, "account_closed": account, "credits_lost": lost,
		"legs": [{"account": account, "delta": -lost}]}
	_append_receipt(operation_id, record)
	return {"ok": true, "receipt": record.duplicate(true),
		"credits_lost": lost}

## Frozen Rust ShipEconomy.credits -> ShipCrew.wages_credits. Crew
## wages are nonspendable accrued savings in the ECS crew component,
## NOT a parallel tradable N9 wallet. The live economic supply drops
## by this paid amount. This one-leg receipt proves the actual source
## debit instead of silently erasing ship credits or minting a payee.
func pay_native_ship_crew(operation_id: String, ship_account: String,
		ship_id: String, amount: int, tick: int) -> Dictionary:
	if operation_id.is_empty() or ship_id.is_empty() or tick < 0 or amount <= 0:
		return {"ok": false, "reason": "invalid_native_crew_wage"}
	if ship_account != "ship:" + ship_id or not _balances.has(ship_account):
		return {"ok": false, "reason": "missing_native_ship_wallet"}
	if _has_receipt_id(operation_id):
		return {"ok": false, "reason": "native_crew_wage_replay"}
	if int(_balances[ship_account]) < amount:
		return {"ok": false, "reason": "unfunded_native_crew_wage"}
	_balances[ship_account] = int(_balances[ship_account]) - amount
	var receipt: Dictionary = {"id": operation_id, "tick": tick,
		"kind": "native_ship_crew_wages", "ship_id": ship_id,
		"wages_credits_accrued": amount,
		"legs": [{"account": ship_account, "delta": -amount}]}
	_append_receipt(operation_id, receipt)
	return {"ok": true, "receipt": receipt.duplicate(true), "amount": amount}


func snapshot() -> Dictionary:
	# The N38 version-1 envelope and ORIGINAL insertion order are retained.
	# Export is intentionally full and detached at a real save/proof boundary.
	return {"version": 1, "balances": _balances.duplicate(true),
		"receipts": _snapshot_receipts()}

## A trusted, owned N9 transaction branch. The source ledger has already
## validated each receipt on its original creation or untrusted N38 restore.
## Snapshot() followed by restore() deep-copied the growing journal twice
## AND rechecked all old receipts on every ordinary paid operation.
## Historical receipts now use persistent copy-on-write partitions:
## fork cost is proportional to active account count + fixed shard count,
## NOT historical receipt count. No old receipt map is writable by child.
## External N38 restore remains strict and re-validates all history.
func fork() -> RefCounted:
	var child: RefCounted = get_script().new()
	child.set("_balances", _balances.duplicate(true))
	child.set("_receipt_partitions", _receipt_partitions.duplicate())
	child.set("_receipt_order_chunks", _receipt_order_chunks.duplicate())
	child.set("_receipt_count", _receipt_count)
	child.set("_receipt_kind_counts", _receipt_kind_counts.duplicate())
	child.set("_flat_receipt_cache", _flat_receipt_cache)
	child.set("_flat_cache_count", _flat_cache_count)
	return child

## Validate old immutable N9 receipt provenance by scanning the existing
## internal receipts, without materializing a complete duplicate history.
## No live receipt row or collection is returned to the caller.
func receipt_count() -> int:
	return _receipt_count

## O(1) exact count of immutable N9 receipts of a given kind. This is a
## read-only diagnostic/provenance aggregate, not an authorization oracle.
## Empty or unknown kinds return zero; the original receipt order is unchanged.
func receipt_kind_count(kind: String) -> int:
	if kind.is_empty():
		return 0
	return int(_receipt_kind_counts.get(kind, 0))

## O(1) operation-ID provenance lookup over the authoritative immutable
## receipt shards. A caller receives a fully detached record, never a mutable
## alias to a ledger shard. Missing IDs return an empty dictionary.
## This is deliberately read-only; it cannot bypass commit/restore checks.
func receipt_copy(operation_id: String) -> Dictionary:
	if operation_id.is_empty() or not _has_receipt_id(operation_id):
		return {}
	return _receipt_at(operation_id).duplicate(true)


## B-owned bounded provenance lookup for N39 consumers that already know the
## operation IDs they need to verify. Unlike snapshot(), this never copies
## unrelated historical receipts. Every returned row is detached from N9 and
## from other returned rows; absent/duplicate/empty IDs fail closed.
## No balances or receipt history are modified by this query.
func receipts_for_operations(operation_ids: Array) -> Dictionary:
	var found: Dictionary = {}
	for value in operation_ids:
		if not (value is String) or value.is_empty() or found.has(value):
			return {"ok": false, "reason": "invalid_or_duplicate_operation_id"}
		if not _has_receipt_id(value):
			return {"ok": false, "reason": "missing_operation_id"}
		found[value] = _receipt_at(value).duplicate(true)
	return {"ok": true, "receipts": found}


## Read-only proof for a bounded set of known operation IDs. N39 can check
## committed kind/tick/legs without exporting a deep copy of the entire N9
## history or exposing mutable internal receipts. Every requested field is
## compared against the original immutable row; no partial success is returned.
## Expected rows must explicitly contain id, kind, tick and legs.
func verify_operation_provenance(expected_rows: Array) -> bool:
	var seen: Dictionary = {}
	for expected in expected_rows:
		if not (expected is Dictionary):
			return false
		if not expected.has("id") or not expected.has("kind") or not expected.has("tick") or not expected.has("legs"):
			return false
		var id: Variant = expected["id"]
		if not (id is String) or id.is_empty() or seen.has(id):
			return false
		if not (expected["kind"] is String) or typeof(expected["tick"]) != TYPE_INT:
			return false
		if not (expected["legs"] is Array) or not _has_receipt_id(id):
			return false
		seen[id] = true
		var stored: Dictionary = _receipt_at(id)
		if stored.get("id") != id or stored.get("kind") != expected["kind"]:
			return false
		if stored.get("tick") != expected["tick"] or stored.get("legs") != expected["legs"]:
			return false
	return true


func retains_receipts(candidate: Dictionary) -> bool:
	for chunk in _receipt_order_chunks:
		for id in chunk:
			if candidate.get(id, null) != _receipt_at(str(id)):
				return false
	return true

## Read-only N39 verification of wallet balances for operations that can
## mutate only the detached ship domain (not the authoritative ledger).
## Return a detached copy: callers cannot edit our live private accounts.
## Full snapshot() remains mandatory for money changes, N9 receipt proofs
## and N38 persistence.
func balances_snapshot() -> Dictionary:
	return _balances.duplicate(true)

func restore(data: Dictionary) -> bool:
	if data.get("version") != 1 or not (data.get("balances") is Dictionary) or not (data.get("receipts") is Dictionary):
		return false
	var candidate: Dictionary = data["balances"]
	for account in candidate:
		if not _valid_account(account) or not _valid_amount(candidate[account]):
			return false
	var receipts: Dictionary = data["receipts"]
	for key in receipts:
		if not _valid_account(key) or not (receipts[key] is Dictionary):
			return false
		if receipts[key].get("id") != key or not (receipts[key].get("legs") is Array):
			return false
	# Build the complete immutable index locally before publishing ANY
	# imported account/receipt. This is an untrusted N38/staged boundary.
	var partitions: Array = []
	partitions.resize(RECEIPT_PARTITIONS)
	for i in range(RECEIPT_PARTITIONS):
		partitions[i] = {}
	var order_chunks: Array = []
	var next_count: int = 0
	var next_kind_counts: Dictionary = {}
	for id in receipts:
		var bucket: int = _bucket_index(str(id))
		var target: Dictionary = partitions[bucket]
		target[id] = (receipts[id] as Dictionary).duplicate(true)
		var last: int = order_chunks.size() - 1
		if last < 0 or (order_chunks[last] as Array).size() >= ORDER_CHUNK_SIZE:
			order_chunks.append([id])
		else:
			(order_chunks[last] as Array).append(id)
		next_count += 1
		var kind: Variant = receipts[id].get("kind", null)
		if kind is String:
			next_kind_counts[kind] = int(next_kind_counts.get(kind, 0)) + 1
	_balances = candidate.duplicate(true)
	_receipt_partitions = partitions
	_receipt_order_chunks = order_chunks
	_receipt_count = next_count
	_receipt_kind_counts = next_kind_counts
	_flat_receipt_cache = {}
	_flat_cache_count = -1
	return true

func _valid_account(value: Variant) -> bool:
	return value is String and not value.is_empty()

func _valid_amount(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0
