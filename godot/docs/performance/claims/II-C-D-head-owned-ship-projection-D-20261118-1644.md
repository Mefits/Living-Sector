# Astra II-C — Head owned-ship projection
STATUS: IN_PROGRESS
OWNER: D
TIME: 2026-11-18 16:44 MSK
BASE_SHA: 7cb81ba1995e9fc8c22eb055c1df722d40aa8973
ASTRA: II-C repeated faction/Head scans, bounded owned roster and deterministic ordering.
INTENDED_FILES: godot/scripts/sim/phase2/unified_native_hybrid_planning.gd; godot/tests/p2_perf_d_head_owned_ship_projection_20261118.gd
PLAN: collapse the faction ship scan and owned-ship DTO projection into one read of each ship, retain canonical sorted ship IDs and cargo validation order; targeted positive/negative snapshot oracle including owner changes, malformed cargo and detached outputs.
TEST: NOT_RUN
