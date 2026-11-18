# Astra II-C — Head owned-ship projection
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
TIME: 2026-11-18 16:44 MSK
BASE_SHA: 7cb81ba1995e9fc8c22eb055c1df722d40aa8973
ASTRA: II-C repeated faction/Head scans, bounded owned roster and deterministic ordering.
INTENDED_FILES: godot/scripts/sim/phase2/unified_native_hybrid_planning.gd; godot/tests/p2_perf_d_head_owned_ship_projection_20261118.gd
PLAN: collapse the faction ship scan and owned-ship DTO projection into one read of each ship, retain canonical sorted ship IDs and cargo validation order; targeted positive/negative snapshot oracle including owner changes, malformed cargo and detached outputs.
CODE_SHA: 02063f29779118bec502ac9e4c6eed4d13807b61
TEST_SHA: 566ad3716bf0ae776787bfa6c59dc3aa9d22a13c
TEST: NOT_RUN (Godot unavailable; GitHub Actions deliberately not triggered)
PERFORMANCE: NOT_MEASURED
RESULT: Capture-local borrowed ship roster avoids second global ship map lookup for each owned ship. Capture-local selected contract rows/status avoid second board lookup and repeated status normalization. No cross-tick cache or retained World references. Canonical sorted IDs and post-sort cargo validation retained.
REGRESSION: 180 mixed-owner ships and contracts, old two-pass exact DTO oracle, owner/status transfer between captures, transit, cargo negative rejection, and World alias isolation.
NEXT: Astra II-C market/faction repeated global scans: identify a bounded per-phase ownership roster shared safely by the actual Head callers, without cross-tick caching; benchmark early/late paid ticks once runtime testing is authorized.

