# Astra II-C D — N129 tax-only population projection
STATUS: IN_PROGRESS
OWNER: D
START: 2026-11-19 13:37 MSK
BASE_SHA: 6ce1f596f5b06ad48a096de95d819a9f8db7babd
ASTRA: II-C station/faction/market repeated scans, read-only projections
INTENDED_FILES: godot/scripts/sim/phase2/unified_native_faction_finance_phase.gd; godot/tests/p2_perf_d_n129_tax_only_projection.gd
SCOPE: Remove redundant household DTO construction on tax-only paid cycles; preserve sorted population_wealth, tax/bailout transfers and relief outcomes; validate missing sources, negative cases and per-call mutation invalidation.
TEST: oracle tax-only and relief-due, negative invalid state, World unchanged.
