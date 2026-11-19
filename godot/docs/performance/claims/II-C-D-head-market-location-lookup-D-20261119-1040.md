# Astra II-C D — Head market location lookup
STATUS: BLOCKED
OWNER: D
TIME: 2026-11-19 10:40 MSK
BASE FILE SHA: 11933eccac3cab1041906f18aa6d17e0811e8474
ASTRA: station/faction/market rosters; avoid repeated full scans; exact Head decisions and market ordering.
INTENDED: godot/scripts/sim/phase2/unified_native_hybrid_planning.gd; godot/tests/p2_perf_d_head_market_location_lookup.gd
PLAN: derive candidate market locations from owned facility locations rather than scan every market per faction; preserve lexicographic market order, ownership/mismatch failure, detached DTO; independent naive oracle and negative mutation cases.
TEST: NOT_RUN
CODE SHA: NONE
BLOCKER: A location-keyed lookup cannot preserve the existing n100_wrong_source_market_owner error for a market at a different location but owned by this faction. A safe replacement requires a complete owner-to-market reverse index shared across Head calls, with an explicit invalidation boundary at the actual caller. This run did not establish that boundary; no source mutation was made.
NEXT: locate N121 multi-faction invocation and implement scoped owner reverse index plus oracle including mismatched owner-location.

