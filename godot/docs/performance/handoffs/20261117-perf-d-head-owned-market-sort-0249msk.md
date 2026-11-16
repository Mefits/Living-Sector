# PERF D — Head owned-market sort (17.11.2026, 02:49 MSK)

- Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262. No merge or force push.
- Code commit: `198d7cf4444b38737880970938815935b1a451b4` — `godot/scripts/sim/phase2/unified_native_hybrid_planning.gd`.
- Test commit: `293b914299f43a65afa84957413dc01cc5b1189e` — `godot/tests/p2_perf_d_head_market_subset_oracle_20261117.gd`.
- The actual Head.capture path previously sorted every global market location once per faction, then filtered by facility owner. Now scans all markets for ownership and sorts only selected locations; preserves lexicographic order, validation of owner location, and detached stock/demand/prices.
- Negative oracle: 240 markets, owner reassignment, facility deletion, wrong-location owner rejection, and mutable alias check against World.
- Status: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime benchmark, no measured acceleration. Expected sort work O(M log M) -> O(M + K log K), M=global markets, K=owned markets; full scan remains O(M).
- Baseline reference: #43856475886 markets/factions ~131ms each per tick in late 601–900 window, not attribution to this site. #43972442164 passed 500 ticks but predates this patch. No new CI.
- Did not touch N152, N9, N39, N158, prices, RNG, Head search budget, contracts or cadence.
- Next: run this oracle and same-seed early/late Head site timing with owner counts and p95; then profile remaining full market scans/DTO. Require N38/N39/BT parity at shared checkpoint.
