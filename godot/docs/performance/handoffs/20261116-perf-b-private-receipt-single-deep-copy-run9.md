# PERF B · paid append: remove duplicate private receipt deep copy (16.11.2026)

## Commits
- Code: `0594ed419142ef4873ee394f51f7e36417b479a5`, `godot/scripts/sim/economy/credit_ledger.gd`
- Targeted negative regression: `eec96f358356ca8f89b8bdc97f1ec43fc2a1b225`, `godot/tests/p2_perf_b_private_receipt_append_no_double_copy_check.gd`

## Root and bounded change
Every successful `Ledger.commit()` deep-copied untrusted `legs` into a private receipt, then `_append_receipt()` deep-copied that entire receipt **again**, then returned another detached receipt copy to the caller. The extra second copy was in the actual paid transaction path, not a detached helper. The other two copies remain essential. All three append callers (`commit`, `close_removed_entity_account`, `pay_native_ship_crew`) construct their own private record and never expose it: only detached public copies are returned. `_append_receipt` now publishes that private record directly into the new COW shard. This removes one receipt-deep-copy per committed operation; no data formats or authority changes.

## Safety / verification
- Test verifies nested caller-leg and returned-receipt mutation cannot corrupt N9, fork isolation, duplicate operation rejection, full snapshot detachment, index audit and N38 v1 restore parity.
- Code inspected in current branch; `CODE_UNVERIFIED`, `TEST_ADDED_NOT_RUN` (no Godot runtime execution in this shift).
- No measured TPS gain yet; one redundant deep copy eliminated per real append. The late-tick 137→839ms degradation is **not** claimed fixed.
- No changes to N39, N158, clock, source cadence, market prices, money rules or N38 format.

## Next actionable step
In one shared bounded CI checkpoint run `godot --headless --path godot --script res://tests/p2_perf_b_private_receipt_append_no_double_copy_check.gd` and existing N9/N38 negative suite. Enable `LS_PROFILE_N9_APPEND=1` on a same-seed bounded phase run and compare append_calls/append_usec/snapshot_usec and paid tick CPU before/after. If N9 contributes only a small fraction of growing ship/dock/market phases, hand off the negative finding and do not add another speculative N9 index.
