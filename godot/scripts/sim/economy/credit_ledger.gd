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
## Wider bounded COW fanout: each real paid append copies one shard.
## 1024 reduces old-receipt rows copied per append by ~4x at equal journal
## size vs 256; fork copies a fixed 1024-entry header, N38 stays version 1.
## Benchmark required: this is an unverified throughput trade-off.
const RECEIPT_PARTITIONS: int = 1024
const ORDER_CHUNK_SIZE: int = 64
var _receipt_partitions: Array = []
var _receipt_order_chunks: Array = []
var _receipt_count: int = 0
## Trusted fork lineage: only used to narrow an existing full provenance proof.
## Generation changes on every append/restore, including equal-count restore.
var _receipt_generation: int = 0
# Provenance must not keep every previous committed Ledger alive.
# The child owns its COW shard references, not its parent ledger object.
var _fork_source: WeakRef = null
var _fork_source_generation: int = -1
var _fork_changed_shards: Dictionary = {}
# Experimental: a shard detached by this generation may accept another
# append without recopying, until a fork shares it. Disabled until parity CI.
var _reuse_private_shards: bool = OS.get_environment("LS_N9_PRIVATE_SHARD_REUSE") == "1"
var _private_shards: Dictionary = {}
# The current last order chunk is private only after its first detach.
# A fork invalidates ownership in both parent and child.
var _private_order_chunk: bool = false
## Exact per-kind counts, updated only on committed append or validated restore.
## A fork owns its counter dictionary: never mutate the parent's counters.
var _receipt_kind_counts: Dictionary = {}
## Only trusted private receipt records live in this flattened read cache.
## It is NEVER exposed to callers; snapshot() returns a detached deep copy.
## The flattened map is rebuilt once per changed receipt generation, and
## otherwise reused across repeated N39 proofs/saves (many per tick).
var _flat_receipt_cache: Dictionary = {}
var _flat_cache_count: int = -1

## Opt-in paid-path instrumentation; off by default and never serialized.
## LS_PROFILE_N9_APPEND=1: time real committed receipt detach and full
## snapshot materialization, not detached benchmark helpers.
var _profile_append: bool = OS.get_environment("LS_PROFILE_N9_APPEND") == "1"
var _profile_append_calls: int = 0
var _profile_append_usec: int = 0
var _profile_append_max_usec: int = 0
var _profile_append_old_shard_rows: int = 0
var _profile_snapshot_calls: int = 0
var _profile_snapshot_usec: int = 0
var _profile_snapshot_max_usec: int = 0

func paid_path_profile() -> Dictionary:
	return {"enabled": _profile_append, "receipt_count": _receipt_count,
		"append_calls": _profile_append_calls,
		"append_usec": _profile_append_usec,
		"append_max_usec": _profile_append_max_usec,
		"append_old_shard_rows": _profile_append_old_shard_rows,
		"snapshot_calls": _profile_snapshot_calls,
		"snapshot_usec": _profile_snapshot_usec,
		"snapshot_max_usec": _profile_snapshot_max_usec}


## A trusted fork replaces the entire partition header immediately. Avoid
## constructing 1024 throwaway empty shard dictionaries on EVERY paid fork.
## Normal construction and N38 restore still initialize all shards.
func _init(trusted_fork: bool = false) -> void:
	if trusted_fork:
		return
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
	var started_usec: int = Time.get_ticks_usec() if _profile_append else 0
	var old_shard_rows: int = (_receipt_partitions[bucket] as Dictionary).size() if _profile_append else 0
	# A previously empty shard has no historical rows to detach. The
	# new dictionary is private to this ledger, including after a fork;
	# populated shards still require COW to protect parent/child history.
	var old_shard: Dictionary = _receipt_partitions[bucket]
	var detached: Dictionary
	if _reuse_private_shards and _private_shards.has(bucket):
		# Only this ledger owns the dictionary since its last fork.
		detached = old_shard
	else:
		detached = {} if old_shard.is_empty() else old_shard.duplicate()
		if _reuse_private_shards:
			_private_shards[bucket] = true
	# All callers construct a private record and return only a detached copy.
	# commit() already detached the untrusted legs before creating this row;
	# duplicating the entire row here repeated the deep copy on every paid leg.
	# Published shards remain immutable after assignment and fork shares only
	# those immutable records. No caller receives this private row directly.
	detached[id] = record
	_receipt_partitions[bucket] = detached
	_receipt_generation += 1
	if _fork_source != null:
		_fork_changed_shards[bucket] = true
	var last: int = _receipt_order_chunks.size() - 1
	if last < 0 or (_receipt_order_chunks[last] as Array).size() >= ORDER_CHUNK_SIZE:
		_receipt_order_chunks.append([id])
		_private_order_chunk = true
	else:
		if _reuse_private_shards and _private_order_chunk:
			# This array has not been shared by a fork since its last detach.
			(_receipt_order_chunks[last] as Array).append(id)
		else:
			var order: Array = (_receipt_order_chunks[last] as Array).duplicate()
			order.append(id)
			_receipt_order_chunks[last] = order
			_private_order_chunk = true
	_receipt_count += 1
	var kind: Variant = record.get("kind", null)
	if kind is String:
		_receipt_kind_counts[kind] = int(_receipt_kind_counts.get(kind, 0)) + 1
	# Rebuilding is delayed until a real full N38/provenance snapshot.
	# A fork that still sees older immutable shards retains its own cache.
	# A cache already invalidated by an earlier paid append must not be
	# replaced with another empty Dictionary on every subsequent append.
	# Release a previously materialized full-history cache on the FIRST
	# invalidation; later paid appends do not allocate redundant empty maps.
	if _flat_cache_count >= 0:
		_flat_receipt_cache = {}
		_flat_cache_count = -1
	if _profile_append:
		var elapsed: int = maxi(0, Time.get_ticks_usec() - started_usec)
		_profile_append_calls += 1
		_profile_append_usec += elapsed
		_profile_append_max_usec = maxi(_profile_append_max_usec, elapsed)
		_profile_append_old_shard_rows += old_shard_rows

func _snapshot_receipts() -> Dictionary:
	var started_usec: int = Time.get_ticks_usec() if _profile_append else 0
	if _flat_cache_count != _receipt_count:
		var ordered: Dictionary = {}
		for chunk in _receipt_order_chunks:
			for id in chunk:
				# Order chunks contain only String IDs from committed receipts or
				# validated restore. Avoid converting every ID on every rebuild.
				# The final native deep copy still detaches every external row.
				ordered[id] = _receipt_at(id)
		_flat_receipt_cache = ordered
		_flat_cache_count = _receipt_count
	var result: Dictionary = _flat_receipt_cache.duplicate(true)
	if _profile_append:
		var elapsed: int = maxi(0, Time.get_ticks_usec() - started_usec)
		_profile_snapshot_calls += 1
		_profile_snapshot_usec += elapsed
		_profile_snapshot_max_usec = maxi(_profile_snapshot_max_usec, elapsed)
	return result

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
	if OS.get_environment("LS_PROFILE_LEDGER") != "1":
		return _profile_inner_snapshot()
	var began: int = Time.get_ticks_usec()
	var result: Dictionary = _profile_inner_snapshot()
	_record_profile("snapshot", began)
	return result

func _profile_inner_snapshot() -> Dictionary:
	# The N38 version-1 envelope and ORIGINAL insertion order are retained.
	# Export is intentionally full and detached at a real save/proof boundary.
	# Wallet values are validated integer credits, never nested containers.
	# Shallow duplication is a fully detached N38 balance map and avoids
	# recursively walking an expanding wallet set at each snapshot.
	return {"version": 1, "balances": _balances.duplicate(),
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
	if OS.get_environment("LS_PROFILE_LEDGER") != "1":
		return _profile_inner_fork()
	var began: int = Time.get_ticks_usec()
	var result: RefCounted = _profile_inner_fork()
	_record_profile("fork", began)
	return result

func _profile_inner_fork() -> RefCounted:
	# The new child shares every current shard. Invalidate ownership on
	# the parent as well: it may still receive operations after this fork.
	_private_shards.clear()
	_private_order_chunk = false
	# Fork owns a detached header from the parent; initializing 1024 empty
	# shard dictionaries first is pure allocation overhead at every stage.
	var child: RefCounted = get_script().new(true)
	# All authoritative wallet values are validated i64 integers. A shallow
	# dictionary copy fully isolates the fork; deep recursion is unnecessary
	# on this paid transaction path and must not copy growing receipt history.
	child.set("_balances", _balances.duplicate())
	child.set("_receipt_partitions", _receipt_partitions.duplicate())
	child.set("_receipt_order_chunks", _receipt_order_chunks.duplicate())
	child.set("_receipt_count", _receipt_count)
	child.set("_reuse_private_shards", _reuse_private_shards)
	child.set("_private_shards", {})
	child.set("_private_order_chunk", false)
	child.set("_receipt_generation", _receipt_generation)
	child.set("_fork_source", weakref(self))
	child.set("_fork_source_generation", _receipt_generation)
	child.set("_fork_changed_shards", {})
	child.set("_receipt_kind_counts", _receipt_kind_counts.duplicate())
	child.set("_flat_receipt_cache", _flat_receipt_cache)
	child.set("_flat_cache_count", _flat_cache_count)
	# Preserve opt-in paid-path counters across authoritative COW generations.
	# Otherwise each committed fork resets the totals and late-tick append/
	# snapshot costs appear to vanish. Counters remain diagnostic-only and
	# are never included in N38 snapshots or shared as mutable containers.
	if _profile_append:
		child.set("_profile_append_calls", _profile_append_calls)
		child.set("_profile_append_usec", _profile_append_usec)
		child.set("_profile_append_max_usec", _profile_append_max_usec)
		child.set("_profile_append_old_shard_rows", _profile_append_old_shard_rows)
		child.set("_profile_snapshot_calls", _profile_snapshot_calls)
		child.set("_profile_snapshot_usec", _profile_snapshot_usec)
		child.set("_profile_snapshot_max_usec", _profile_snapshot_max_usec)
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

## B-owned read-only bounded diagnostic for late-tick ledger growth.
## No receipt snapshots, row duplication or full-history traversal. Reports
## shard sizes to expose the cost of copy-on-write _append_receipt(), where
## each new commit currently duplicates its selected existing shard.
## This is an instrumentation API, not a financial authorization boundary.
func receipt_storage_profile() -> Dictionary:
	var largest_shard: int = 0
	var occupied_shards: int = 0
	var sum_squared_shard_sizes: int = 0
	var indexed_receipts: int = 0
	for shard_value in _receipt_partitions:
		if not (shard_value is Dictionary):
			return {"ok": false, "reason": "invalid_shard"}
		var size: int = (shard_value as Dictionary).size()
		if size > 0:
			occupied_shards += 1
		largest_shard = maxi(largest_shard, size)
		indexed_receipts += size
		# For a uniform next receipt ID, the expected old rows copied by
		# a COW shard detach are sum(n_i^2)/sum(n_i). Integer math only.
		sum_squared_shard_sizes += size * size
	if indexed_receipts != _receipt_count:
		return {"ok": false, "reason": "count_mismatch"}
	return {"ok": true, "receipts": _receipt_count,
		"occupied_shards": occupied_shards,
		"largest_shard": largest_shard,
		"mean_shard_rows": float(_receipt_count) / float(RECEIPT_PARTITIONS),
		"estimated_cow_rows_per_append": float(sum_squared_shard_sizes) /
			float(maxi(1, indexed_receipts)),
		"order_chunks": _receipt_order_chunks.size(),
		"flat_cache_valid": _flat_cache_count == _receipt_count}

## O(1) operation-ID provenance lookup over the authoritative immutable
## receipt shards. A caller receives a fully detached record, never a mutable
## alias to a ledger shard. Missing IDs return an empty dictionary.
## This is deliberately read-only; it cannot bypass commit/restore checks.
## Full O(history) diagnostic oracle for the O(1) kind counters and the
## persistent shard/order index. Never called on the paid transaction hot path.
## Reads private immutable rows only: no snapshot copies or mutable exposure.
## Detects duplicate/missing order IDs, wrong shard membership, stale counters,
## and unexpected extra shard entries. Legacy receipts without kind are valid.
func audit_receipt_index() -> bool:
	# A diagnostic must reject damaged private index structure rather than
	# indexing out of bounds or coercing a non-dictionary shard. Never repair
	# authoritative receipts during an audit.
	if _receipt_partitions.size() != RECEIPT_PARTITIONS:
		return false
	for shard in _receipt_partitions:
		if not (shard is Dictionary):
			return false
	var seen: Dictionary = {}
	var actual_kinds: Dictionary = {}
	var count: int = 0
	for chunk in _receipt_order_chunks:
		if not (chunk is Array) or chunk.is_empty() or chunk.size() > ORDER_CHUNK_SIZE:
			return false
		for id in chunk:
			if not (id is String) or id.is_empty() or seen.has(id):
				return false
			var shard: Dictionary = _receipt_partitions[_bucket_index(id)]
			if not shard.has(id) or not (shard[id] is Dictionary):
				return false
			var row: Dictionary = shard[id]
			if row.get("id") != id:
				return false
			seen[id] = true
			count += 1
			var kind: Variant = row.get("kind", null)
			if kind is String:
				actual_kinds[kind] = int(actual_kinds.get(kind, 0)) + 1
	if count != _receipt_count or actual_kinds != _receipt_kind_counts:
		return false
	var shard_total: int = 0
	for i in range(RECEIPT_PARTITIONS):
		var shard: Dictionary = _receipt_partitions[i]
		for id in shard:
			if not (id is String) or not seen.has(id) or _bucket_index(id) != i:
				return false
			shard_total += 1
	return shard_total == count


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
		# Optional receipt metadata (write-offs, crew accrual and future
		# provenance fields) is part of the proof too. Never accept a forged
		# field just because the ordinary payment legs happen to match.
		for field in expected:
			if not stored.has(field) or stored[field] != expected[field]:
				return false
	return true


## Exact bounded N9 provenance oracle for transaction staging. Unlike
## verify_operation_provenance(), this rejects omitted metadata as well as
## forged metadata. An expected row must be the ENTIRE original receipt.
## O(requested IDs), never a full history snapshot, and no mutable alias.
## Empty proofs fail closed; no implicit authorization of an empty batch.
func verify_exact_operation_receipts(expected_rows: Array) -> bool:
	if expected_rows.is_empty():
		return false
	var seen: Dictionary = {}
	for value in expected_rows:
		if not (value is Dictionary):
			return false
		var row: Dictionary = value
		var id: Variant = row.get("id", null)
		if not (id is String) or id.is_empty() or seen.has(id):
			return false
		seen[id] = true
		if not _has_receipt_id(id):
			return false
		var stored: Dictionary = _receipt_at(id)
		if row.size() != stored.size():
			return false
		for field in stored:
			if not row.has(field) or row[field] != stored[field]:
				return false
	return true


## Read-only, bounded paid-leg provenance aggregate for a caller-supplied set
## of operation IDs. Unlike a full N9 snapshot, touches only the requested
## immutable receipts. It is NOT a transfer/authorization API: the N39 caller
## still validates physical cargo, contract ownership and all cross-domain
## invariants. Single-leg write-offs/wages are deliberately rejected here.
## Fail closed on duplicates, malformed legs, negative credits or i64 overflow.
## Returns detached account totals and signed net legs (always zero).
func paid_leg_totals_for_operations(operation_ids: Array) -> Dictionary:
	if operation_ids.is_empty():
		return {"ok": false, "reason": "empty_proof"}
	var seen: Dictionary = {}
	var account_totals: Dictionary = {}
	var debits: int = 0
	var credits: int = 0
	for id_value in operation_ids:
		if not (id_value is String) or id_value.is_empty() or seen.has(id_value):
			return {"ok": false, "reason": "invalid_or_duplicate_operation_id"}
		seen[id_value] = true
		if not _has_receipt_id(id_value):
			return {"ok": false, "reason": "missing_operation_id"}
		var receipt: Dictionary = _receipt_at(id_value)
		if receipt.get("id") != id_value or not (receipt.get("legs") is Array):
			return {"ok": false, "reason": "invalid_receipt"}
		var legs: Array = receipt["legs"]
		if legs.size() < 2:
			return {"ok": false, "reason": "not_a_paid_transfer"}
		var receipt_debits: int = 0
		var receipt_credits: int = 0
		for leg in legs:
			if not (leg is Dictionary) or not leg.has("account") or not leg.has("delta"):
				return {"ok": false, "reason": "invalid_leg"}
			var account: Variant = leg["account"]
			var amount: Variant = leg["delta"]
			if not _valid_account(account) or typeof(amount) != TYPE_INT:
				return {"ok": false, "reason": "invalid_leg"}
			# -2^63 cannot be negated in a signed 64-bit credit total.
			if amount == -MAX_CREDITS - 1:
				return {"ok": false, "reason": "integer_overflow"}
			var prior: int = int(account_totals.get(account, 0))
			if amount > 0:
				if prior > MAX_CREDITS - amount or credits > MAX_CREDITS - amount or (
					receipt_credits > MAX_CREDITS - amount):
					return {"ok": false, "reason": "integer_overflow"}
				credits += amount
				receipt_credits += amount
			else:
				if prior < -MAX_CREDITS - amount or debits > MAX_CREDITS + amount or (
					receipt_debits > MAX_CREDITS + amount):
					return {"ok": false, "reason": "integer_overflow"}
				debits -= amount
				receipt_debits -= amount
			account_totals[account] = prior + amount
		if receipt_debits == 0 or receipt_debits != receipt_credits:
			return {"ok": false, "reason": "unbalanced_receipt"}
	if debits != credits:
		return {"ok": false, "reason": "unbalanced_batch"}
	return {"ok": true, "operations": seen.size(), "debits": debits,
		"credits": credits, "account_deltas": account_totals}


func retains_receipts(candidate: Dictionary) -> bool:
	# A provenance candidate must contain exactly the committed history.
	# Reject truncated or padded maps in O(1) before walking growing order
	# chunks. Previously extra operation IDs were silently accepted.
	if candidate.size() != _receipt_count:
		return false
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
	# All balances are validated integer credits; a shallow dictionary copy
	# detaches the caller without recursively walking immutable scalar values.
	return _balances.duplicate()

func restore(data: Dictionary) -> bool:
	if OS.get_environment("LS_PROFILE_LEDGER") != "1":
		return _profile_inner_restore(data)
	var began: int = Time.get_ticks_usec()
	var result: bool = _profile_inner_restore(data)
	_record_profile("restore", began)
	return result

func _profile_inner_restore(data: Dictionary) -> bool:
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
	_receipt_generation += 1
	_fork_source = null
	_fork_source_generation = -1
	_fork_changed_shards = {}
	_private_shards = {}
	_receipt_kind_counts = next_kind_counts
	_flat_receipt_cache = {}
	_flat_cache_count = -1
	return true

func _valid_account(value: Variant) -> bool:
	return value is String and not value.is_empty()

func _valid_amount(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0

# Opt-in bounded aggregate timings; never part of N9 state or N38.
static var profile_cost: Dictionary = {}
static func _record_profile(kind: String, began: int) -> void:
	var row: Dictionary = profile_cost.get(kind, {"calls": 0, "usec": 0})
	row["calls"] += 1
	row["usec"] += Time.get_ticks_usec() - began
	profile_cost[kind] = row

## Proof for internal COW transactions. Unchanged shards retain identity;
## changed shards must retain every original immutable row. A restored or
## replaced history cannot acquire this proof merely by matching its count.
func retains_owned_receipts(parent: RefCounted) -> bool:
	if parent.get_script() != get_script() or _receipt_count < parent.receipt_count():
		return false
	var old: Array = parent.get("_receipt_partitions")
	# A direct child knows precisely which immutable COW shards it detached.
	# Parent generation must still match the fork point: a later parent append
	# or even same-count restore invalidates the shortcut. All other cases use
	# the original exhaustive oracle, including unrelated/ancestor ledgers.
	if _fork_source != null and is_same(_fork_source.get_ref(), parent) and (
			_fork_source_generation == int(parent.get("_receipt_generation"))):
		for bucket_value in _fork_changed_shards:
			var bucket: int = int(bucket_value)
			if bucket < 0 or bucket >= RECEIPT_PARTITIONS:
				return false
			if not (_receipt_partitions[bucket] is Dictionary):
				return false
			for id in old[bucket]:
				if not is_same((_receipt_partitions[bucket] as Dictionary).get(id),
						old[bucket][id]):
					return false
		return true
	for i in range(RECEIPT_PARTITIONS):
		if is_same(_receipt_partitions[i], old[i]):
			continue
		for id in old[i]:
			if not is_same((_receipt_partitions[i] as Dictionary).get(id), old[i][id]):
				return false
	return true
