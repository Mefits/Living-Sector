# Astra II-A — N9 immutable paid receipt publication
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
START: 2026-11-18 18:15 MSK
BASE_SHA: f79a75461e73e98198eb317ab9fc577dbfaf7339
ASTRA: II-A, remaining receipt immutability / paid transaction overlay / idempotency
INTENDED_FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_receipt_atomicity.gd
EXPECTED: positive and negative regression for external mutation, failed operations, fork, N38 restore, exact snapshots; no Actions.
RISK: N9 money/receipt exact parity; no default experimental shard reuse.

CODE_SHA: 627f3609d05b419a3eff8731dc5036dbc16da915
TEST_SHA: 83e397ba5005ea2d3334c2d30b004580fcc767dc
FILES: credit_ledger.gd; p2_perf_b_receipt_atomicity.gd
CHANGED: commit() detaches untrusted paid legs and stages public proof before wallet publication; close_removed_entity_account() and pay_native_ship_crew() stage immutable receipts/public proofs before wallet mutations. All three authoritative receipt-writing paths retain existing N9 idempotency and financial guards.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
POSITIVE: paid transfer, write-off, crew wage, fork and N38 restore; NEGATIVE: public proof and input mutation, duplicate payment, unfunded transfer, repeated removal, unfunded wages, restored snapshot alias.
NEXT ASTRA II-A: real late-tick N9 receipt shard detach/snapshot cost and opt-in shard reuse same-seed parity before any default switch; Astra III: bounded N38 restart failure tests.
