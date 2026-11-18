# II-E · Bounded N158 native ship subphase samples
STATUS: IN_PROGRESS
Owner: E
Started: 2026-11-18 10:51 MSK
Base PR #262 HEAD: fcce8fad71114e2f8c79f8eb8d8f0292d141c1ca
Source: ASTRA_FIVE_SHIFTS_RU.md, E benchmark acceptance / bounded profiling; checkpoint 20261117 independent audit, N158 unbounded _profile_ship_samples.
Intended files: godot/scripts/sim/phase2/n158_production_runtime.gd; godot/tests/p2_perf_e_n158_bounded_ship_profile.gd.
Expected check: bounded memory under opt-in profiling, newest-window p95, negative regression for >cap samples and preserved phase output; no simulation changes.
