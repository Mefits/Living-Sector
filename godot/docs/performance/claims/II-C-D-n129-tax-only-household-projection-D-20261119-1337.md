# Astra II-C D — N129 eligible household projection
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
START: 2026-11-19 13:37 MSK
BASE_SHA: 6ce1f596f5b06ad48a096de95d819a9f8db7babd
ASTRA: II-C station/faction/market repeated scans, read-only projections
INTENDED_FILES: godot/scripts/sim/phase2/unified_native_faction_finance_phase.gd; godot/tests/p2_perf_d_n129_tax_only_projection.gd
SCOPE: Tax cadence is a subset of relief cadence, so tax-only paid cycles do not exist. Instead, avoid constructing and deep-copying noneligible household DTOs on every relief cycle; preserve sorted population_wealth, tax/bailout transfers and relief outcomes; validate missing sources, negative cases and per-call mutation invalidation.
TEST: oracle relief-due, tax+relief and no-op, negative invalid state, World unchanged.

CODE_SHA: 26fd293a57b20b88fcc4e13324b4223fda5513ff
TEST_SHA: 66eabe70d8afe9d46c0a102aea66a4f7da7a9c95
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
CHANGED: unified_native_faction_finance_phase.gd::propose. Complete sorted population_wealth remains, but household DTOs passed to Relief.apply are restricted to live faction and [0, HOUSEHOLD_MINIMUM) wealth. No cross-call cache. Existing N129 full-household oracle reused by new targeted 1602-row test, covering 25/200 cadence, ownership/wealth/removal changes and negative source registries.
RISK: Requires Godot 4.7.2 execution and exact N39/N9 replay. No benchmark or Actions invoked.
NEXT ASTRA II-C D: profile and optimize remaining repeated Head N121 per-faction scans with a single-call read-view; preserve wrong-source-market-owner validation and contract ordering.
