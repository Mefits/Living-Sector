# PERF D — N150 empty order books (17.11.2026)
- Code: ed9fad27e9f6a1e50da53aa323131aded7d90d55
- Test: 2e50d210d6cb9d05b8f69d3dbe37281a0cab2290
- Files: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_empty_orders_20261117.gd
- Change: avoid per-market empty pending order compaction loop in N150; preserve owned/standalone return shape, nonempty validation, order expiry and alias boundaries.
- TEST EXECUTED: NOT RUN (Godot runtime not used). CODE_UNVERIFIED. No speedup measured, no same-seed parity evidence. Likely minor improvement only; not a claimed late-tick fix.
- Next: bounded N150/Head profile same seed early/late; execute test in shared checkpoint and compare full market/contract/ledger snapshots. Do not duplicate Astra fixes 99ab25e9 / 1676db61.
