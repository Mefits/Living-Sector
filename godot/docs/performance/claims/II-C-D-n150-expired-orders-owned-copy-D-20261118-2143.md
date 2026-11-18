# Astra II-C / D — N150 expired order ownership boundary
STATUS: IN_PROGRESS
OWNER: PERF D
START: 2026-11-18 21:43 MSK
BASE_SHA: bf42a67f5ca932247d0d9b5a94f6ea6a8248c7be
ASTRA: II-C station/faction/market rosters; D markets repeated full scans and owned copies.
SCOPE: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_expired_orders_owned_copy.gd
PLAN: validate all order rows including expired/buyerless; deep-copy only retained order records before tick_one_market, keep source order, independent returned data, identical failure reason, price, stock, history and cadence. No persistent cache.
TEST: positive exact old deep-copy+retain oracle, negative malformed expired rows, nested alias, expiry boundary and paid tick.
