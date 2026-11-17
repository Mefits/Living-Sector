# PERF E — bounded phase window adapter (17.11.2026)
CODE: d73b8ef2364b5a18bba438f8ff8df36809d932b2
TEST: 1bb0d062aa824bb0a479ead62ae6bf84267130fb
FILES: godot/scripts/sim/phase2/n158_worker_request_metrics.gd; godot/tests/p2_perf_e_phase_window_100.gd
TEST EXECUTED: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN.
WHY: strict 100-paid-tick per-phase elapsed wall timing aggregate for ships/dock_queue/markets/factions, rejects missing/negative/duplicate/out-of-order ticks; no World copies, no gameplay changes.
LIMIT: adapter is not yet wired to live native phase profiler; no speedup or runtime measurement claimed. The old 500-tick CI does not cover these commits.
NEXT: connect to existing native phase profiler only at completed paid tick, record 100/300/600/900 windows and exact N38/BT/RNG same-seed parity; avoid 2600/35-minute CI and duplicate Astra fixes.
