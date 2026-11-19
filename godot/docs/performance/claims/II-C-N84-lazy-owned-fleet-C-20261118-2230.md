# II-C N84 lazy owned fleet
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
TIME: 2026-11-18 22:30 Europe/Moscow
BASE_SHA: 87fb8ef8d2a8e3b533688ababf16c3658f12b07a
ASTRA: II-C N84 BT/world hotpath; avoid redundant full fleet row copying while preserving owned result, N14/BT/cargo/contract semantics.
INTENDED_FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_lazy_owned_fleet.gd
EXPECTED_TEST: cached vs original deep-detached fleet oracle; idle/active/contract/travel, source unchanged, output independent, invalid ship negative.
RISK: nested mutable aliases and ordered BT state; only active rows detached before BT, remaining rows detached before return.

CODE_SHA: 4bdf82d24ae07ad22238d5b448ff7cc960c44674
TEST_SHA: 6d9ba36fdff566987c74dc2ec92bc5e943bb9f09
TEST: NOT_RUN
CODE: N84 propose now starts with a shallow private roster, deep-detaches each BT-active ship before N90/BT/N104/N14 writes, and seals all untouched rows exactly once before returning an independent fleet. This replaces eager full-fleet deep copy plus repeated active-row work with proposal-local ownership. No World writes, no changed command order, no N9/N38/N39 modifications.
TEST_COVERAGE: 0/1/24/100/500 rows, nested cargo/memory/BT/transaction mutation, owned vs eager-deep oracle, return alias negatives, real idle propose, malformed active BT failure.
RISK: Godot parser and actual N84 BT/paid-tick parity not executed; no speed measurement.
NEXT_ASTRA: II-C N84/N153 remaining dock occupancy/contract candidate scans with exact BT/cargo/route negatives and 24/100/500 paid fixture.
