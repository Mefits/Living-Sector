# Astra II-C · D · N129 relief eligible producer roster
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
START: 2026-11-19 06:43 MSK
BASE SHA: 9c2533d2cde786bc2ce7b3a2f08de4d8c835659e
ASTRA: II-C station/faction/market rosters; remove repeated full scans and unnecessary projections while preserving finance cadence.
SOURCE: godot/scripts/sim/phase2/unified_native_faction_finance_phase.gd
TEST: godot/tests/p2_perf_d_n129_due_scoped_projections.gd
CODE SHA: 27f122d656bd335ba31c13d05091a265eeb02c85; final source 1744635d255424bfd0f8a70f08f30420d7017d83
TEST SHA: 2eb4c342a2e9a1d0e136a03a52a8ff2fd0b93415
TEST STATUS: NOT_RUN
CODE STATUS: CODE_UNVERIFIED
PERFORMANCE: NOT_MEASURED

Changed the actual N129 relief adapter to prefilter producer DTOs by the exact Relief.apply eligibility predicate: available faction, same-faction market, nonnegative credits below PRODUCER_MINIMUM, and essential farm/refinery for food/water scarcity. The original full facility projection, tax and bailout stages, market owner validation, household projection, and complete final wallet outputs remain intact. Canonical facility ID order is preserved; Relief.apply still independently checks every surviving producer and sorts requests by priority/faction/location/id. No World cache or mutable alias is introduced. This avoids allocating/deep-copying all irrelevant producers on each relief-due tick.

Regression: old full-roster oracle vs new proposal on due/no-op cadence, 363 mixed producers and 240 households, transfer ordering/amounts, mutation between cycles, missing registry, invalid market owner. Test has not been executed. Important cadence observation: tax due 200*m is always also relief due 25*m; an initially attempted tax-only household gate was reverted rather than retaining an unreachable optimization.

NEXT ASTRA II-C: Head/faction repeated scans of growing contracts/facilities, with per-cycle read view and exact decision/order oracle; alternatively event due hotpath only with measured benefit.
