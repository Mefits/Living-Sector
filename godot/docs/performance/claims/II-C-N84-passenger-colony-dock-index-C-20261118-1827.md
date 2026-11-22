# II-C N84 passenger colony dock candidate indexing
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-18 18:27 MSK
BASE SHA: 3fac0a32cc967d682dc636d4bd689f459e5d2953
ASTRA: II-C ships+dock_queue repeated full scans, preserve source-order tie-break and paid physical dock semantics.
INTENDED FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_passenger_dock_index.gd
EXPECTED: call-scoped passenger site candidate roster; unchanged construction direct lookup, receipt/facility live validation, positive/negative original-scan oracle, no cross-tick cache.
CODE SHA: 76309a03d53d8e5b375df411760a0071513d59ea
TEST SHA: 06d2165be53f2860381ddc6cf926d88f0fcff17b
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED

IMPLEMENTED: N84 _real_contract_dock passenger lookup now uses a call-scoped location/faction ordered roster shared by Dock and passenger delivery leaves. Construction direct site lookup and market-station priority unchanged. Receipt, labor, facility type/location/abandonment are still checked live; no World alias stored across proposals. Replaces repeated O(all historical sites) scan with O(1) roster lookup plus matching candidates after one O(sites) build.
REGRESSION: 2000-site original ordered oracle, repeat 40 calls, receipt invalidation, abandoned dock, labor invalidation, ownership change with fresh proposal, construction direct site and market station priority. NOT EXECUTED.
RISK: live mutation of site location/faction within a single N84 proposal would invalidate roster; current N84 only stages ship/BT changes, but verify full replay before acceptance.
NEXT ASTRA II-C: source-level N84/contract dispatch and dock paid-tick measurements, then remaining repeated ship candidate scans with exact BT/cargo/fuel oracle.

