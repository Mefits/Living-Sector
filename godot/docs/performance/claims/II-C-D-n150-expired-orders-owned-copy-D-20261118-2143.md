# Astra II-C / D — N150 expired order ownership boundary
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: PERF D
START: 2026-11-18 21:43 MSK
BASE_SHA: bf42a67f5ca932247d0d9b5a94f6ea6a8248c7be
ASTRA: II-C station/faction/market rosters; D markets repeated full scans and owned copies.
SCOPE: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_expired_orders_owned_copy.gd
PLAN: validate all order rows including expired/buyerless; deep-copy only retained order records before tick_one_market, keep source order, independent returned data, identical failure reason, price, stock, history and cadence. No persistent cache.
TEST: positive exact old deep-copy+retain oracle, negative malformed expired rows, nested alias, expiry boundary and paid tick.

CODE_SHA: fc876d0a41bd96ff9dc6bdf0e1f0e5d6d4efacb0
TEST_SHA: c8c09b3846131cfb578cae31e46050317d8e6f92
TEST: NOT_RUN
PERFORMANCE: NOT_MEASURED
IMPLEMENTED: tick_one_market borrows order books until the canonical late order-processing phase, deep-copies only retained orders, and independently duplicates reserved and extension fields. _retain_orders(..., false) validates discarded malformed rows, preserves buy-before-sell error precedence and source order; price/stock/flow/history logic unchanged. No World aliases returned and no cache lifetime.
ORACLE: fixtures 0/1/51/501/1201 orders, tick 51/100/112, legacy deep-copy-and-filter comparison, reserved/extension alias, invalid expired buy and invalid sell rejection.
RISK: parser and exact replay unverified; manual Godot/Windows tests and same-seed paid-tick performance required. No Actions launched.
NEXT: Astra II-C D — eliminate repeated facility/market roster construction across actual Head/administrator due callsites with ownership/invalidation oracle, or profile N150 retained-order growth on 420/900 paid ticks.
