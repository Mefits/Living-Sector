# Astra II-A — N9 incremental flattened receipt cache

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
START: 2026-11-18 19:16 MSK
BASE SHA: 5032a1e1e7b51a993924f00b3c3549133eec9188
ASTRA: II-A N9 append-only history, owned stage overlays and bounded provenance; avoid repeated full-history scans on paid path.
FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_n9_flat_cache_delta.gd
PLAN: preserve immutable base flattened cache through paid appends and fork, track bounded new receipt IDs, rebuild only delta at snapshot boundary; restore clears lineage. Exact snapshot/order/fork and negative alias/replay oracle.
TEST: targeted positive and negative Godot regression; TEST_NOT_RUN until runtime available.

CODE SHA: c9084dfbdc761db754b6436751c375acecbbc782
TEST SHA: c078cba4cbfa9e17a628c1538d23d37e6e236d47
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
RESULT: _append_receipt preserves immutable flattened base and accumulates new operation IDs; _snapshot_receipts rebuilds by copying base and adding only the delta instead of rescanning every old order chunk; fork duplicates delta IDs while sharing immutable base; restore clears all delta lineage. Existing _flat_cache_count invalidation contract preserved.
ORACLE: 70+65 paid receipts, forked parent/sibling, duplicate and unfunded rejection, full-scan comparison, N38 restore, external mutation isolation. Not executed.
RISK: base dictionary shallow copy still costs O(R) at export, but avoids O(R) shard hash lookups; same-seed profiling required. No default feature flag changed.
NEXT ASTRA II-A: measure paid-path full N9 snapshot cost vs append delta at tick100/300/600/900, then investigate actual receipt history retention/owned stage overlay only if measured.
