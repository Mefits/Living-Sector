# II-C N84 proposal-scoped transit envelope
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
DATE: 2026-11-19 13:32 MSK
BASE_SHA: 1df1ca3672f523cffe8f094004dd0ab7871144e1
ASTRA: II-C ship/contract/dock/route caches; N84/N14 repeated fleet-envelope validation.
CODE_SHA: 4b19a9778bab3ef67bbbafcd9733a8dc94d7997b
CODE_COMMITS: 1e00234fedc680b66c937e1b9f5c36ea46eace09, 4b19a9778bab3ef67bbbafcd9733a8dc94d7997b
TEST_SHA: 780c284fbed72a891f907dd4a7024147427cc4a5
TEST: NOT_RUN
CODE: UNVERIFIED
PERFORMANCE: NOT_MEASURED
FILES: godot/scripts/sim/phase2/unified_ship_phase.gd; godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_transit_envelope.gd
IMPLEMENTED: N84-owned proposal-local envelope validation cached after first scan, with explicit invalidation immediately after BeginTransit. Public preview_depart remains strict uncached by default. Defensive fallback uses the same private envelope only within the synchronous N84 proposal; changes in ship_next_token or fleet size also force rescan. No persistent World/N38 index, no altered N14 physics, cargo/BT/route state, or ledger writes.
REGRESSION: 500 ships; cached vs uncached; transit token changes, corrupt transit, invalid identity, removal, changed cursor, cargo/BT/route ownership, strict public fallback after in-place mutation.
RISK: Proposal-owned mode relies on N84 being the sole writer of transit/identity inside its synchronous call; verify no additional future writers are added without invalidation. Full paid-tick and N38 parity still untested.
NEXT ASTRA II-C: N84/N153 paid-tick fixture with real contracts and docks (24/100/500), strict BT/cargo/fuel/route/N38 oracle; profile residual dock/contract hotpaths before additional indexing.
