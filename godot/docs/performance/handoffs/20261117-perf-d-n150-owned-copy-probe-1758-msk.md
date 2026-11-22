# PERF D — N150 actual owned-copy probe, 17.11.2026 17:58 MSK

CODE COMMIT: 997c0fb3e34f9082f40a7e9c31e0761235edf3e5
TEST COMMIT: e8e5a2fec133f0dc868ce8f3dad1e6864e5a88a6

Files: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_copy_probe_20261117.gd.

Actual paid path: tick_one_market -> market.duplicate(true). Added disabled-by-default probe via configure_copy_probe(true), copy_probe_snapshot() with cumulative calls, copy_us and input trend_rows. No World alias retained, no changes to price, stock, order, cadence or RNG. When disabled, no Time.get_ticks_usec call. Probe is diagnostic only; no measured speedup claimed.

TEST EXECUTED: NOT RUN (no Godot runtime invoked). CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Negative test checks malformed market does not count as copy and returned diagnostic Dictionary does not alias counters.

NEXT: E / bounded CI harness can opt-in configure_copy_probe(true) around same-seed early/late paid tick windows, record copy_us/calls/trend_rows and compare with market-phase CPU. Probe is cumulative; reset between windows. If copy cost materially grows, design safe history ownership boundary with exact N38/restart and price/stock parity before changing the production copy. No new CI launched; earlier #43972442164 does not cover this patch.
