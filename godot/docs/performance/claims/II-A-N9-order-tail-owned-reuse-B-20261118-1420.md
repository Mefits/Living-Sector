# Astra II-A · N9 bounded receipt-order tail ownership
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
START: 2026-11-18 14:20 Europe/Moscow
BASE_SHA: 47323f5b42b632c560bb63b7d005c5732ba6f73f
SOURCE: ASTRA_FIVE_SHIFTS_RU.md / II-A append-only receipt history, owned transaction overlays
FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_order_tail_owned.gd
GOAL: Eliminate redundant repeated COW copies of the bounded receipt order tail between forks, preserve immutable historical order across parent/child, snapshot and restore. Verify same oracle order, alias isolation, duplicate/failed transaction behavior.
TEST: targeted positive and negative regression; NOT_RUN until Godot runtime.

## Result
CODE SHA: ad74044a98c21d0eb3cf772b213f5c6296f8a826
TEST SHA: d02ddf7dad33e6ef3e082e901c0e23c424a67d2e
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
SOURCE: _append_receipt() now mutates an exclusively owned receipt-order tail in default mode instead of duplicating up to 63 IDs on every paid receipt. _profile_inner_fork() already invalidates tail ownership on parent and child, restore() resets it; chunk rollover allocates a new private tail. Receipt shard reuse remains opt-in and untouched. N38 v1 export remains detached and ordered.
REGRESSION: default tail identity across repeated paid appends, parent/child/grandchild detach, immutable snapshots, duplicate and unfunded rejection, 64-ID rollover, exact N38 restore and post-restore detach. Test added but not executed.
RISK: Godot parser/runtime and performance not yet verified; exact full same-seed replay required before acceptance.
NEXT ASTRA II-A: investigate/measure shard-copy cost on real late paid ticks and validate opt-in private-shard reuse against same-seed legacy receipts before enabling it.
