# Astra II-C / D — N150 expired consumption-window copy boundary
STATUS: IN_PROGRESS
OWNER: PERF D
START: 2026-11-18 20:38 MSK
BASE SHA: 6e5deda971f3cda5576fc3e5e7613d39f57cb332
ASTRA: II-C station/faction/market rosters, repeated full scans and growing market histories; D markets 39.43s/300 ticks.
INTENDED FILES: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_window_copy_oracle.gd
PLAN: avoid deep-copying expired consumption samples that the paid N150 tick discards, while retaining validation of all samples, source order and float summation, ownership, demand/price and negative behavior. Target positive+negative old-vs-new oracle.
TEST: NOT_RUN
