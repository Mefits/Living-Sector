# PERF D — N150 paid-tick consumption-window compaction (16.11.2026 22:22 MSK)

- CODE COMMIT: `1f3439ea1993a6377e66852bb8f51ad36b4b20ed`
- TEST COMMIT: `740ce74ab2e061ae6fd997ba58c8ffbb5329b24e`
- Branch: `integration/perf-astra-5-workers-20261116` / draft PR #262
- Code: `godot/scripts/sim/phase1/n150_native_full_market_tick.gd`
- Test: `godot/tests/p2_perf_d_n150_owned_window_compaction_20261116.gd`

## Change
Actual N150 paid market tick previously allocated a fresh `kept` array for every consumption-window commodity on every paid tick, while it already owns a deep-copy of the market. Now it compacts each owned window in place, preserves source order and float addition order, validates every sample before keeping it, and resizes after scanning. No new index, no changed prices, cadence, RNG, World or ledger code. Rejected invalid samples still fail closed, without touching caller's World.

## Evidence / limitations
- TEST EXECUTED: **NOT RUN**; **CODE_UNVERIFIED / TEST_ADDED_NOT_RUN** (Godot runtime unavailable here).
- Targeted regression checks cutoff, retained order, exact observed demand, nested alias isolation, and malformed quantity rejection.
- Expected reduction: one temporary array allocation and its append growth per commodity window per paid market tick. **No measured improvement**; this is not evidence of reduced tick900 CPU cost.
- Baseline #43856475886 with profiler enabled: markets 39.43s and factions 39.34s over ticks 601–900. No same-seed before/after run yet.

## Next
Run targeted Godot test and existing N150 oracle, then bounded same-seed early/late windows, record market phase avg/p95, consumption-window entry counts, allocations, market DTO/copy sites, and exact N9/N39/N38/BT/RNG/contract/cargo parity before accepting. If window compaction is insignificant, focus on measured market DTO/Head growth instead. No CI dispatched for this individual commit.
