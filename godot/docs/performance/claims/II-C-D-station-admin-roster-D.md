# Astra II-C / D — station administration repeated roster scans

STATUS: IN_PROGRESS
OWNER: D
START: 2026-11-18 10:35 MSK
BASE HEAD: cd1ca1dde219100afed61114d0ef4c3bc7165a51
SOURCE: ASTRA_FIVE_SHIFTS_RU.md → II-C station/faction/market rosters (D)
SCOPE: One real station administration repeated-scan hotpath; no N39/N9/N158 edits.
INTENDED FILES: godot/scripts/sim/phase2/unified_native_station_administration_phase.gd; godot/tests/p2_perf_d_station_roster_*.gd
EXPECTED CHECK: deterministic same-order roster and ownership/move/empty negative oracle, no change in decisions or economy; runtime NOT RUN until separate checkpoint.
