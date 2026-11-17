# PERF C · 17.11.2026 · N84 construction dock lookup

CODE COMMIT: 276fc7c2ee198502927dccbf99263dfe47fd8a93
TEST COMMIT: 4388115324e6b9b9c8b49c79cc696a56bd65dd55
Branch: integration/perf-astra-5-workers-20261116, PR #262

Changed `godot/scripts/sim/phase2/unified_ship_ai_execution.gd`: the existing construction direct lookup still called `world.get("construction_sites", {}).keys()` before replacing the resulting 2000+ ID array with a one-element array. Moved the full keys materialization into the passenger-only branch. Construction now allocates one ID and uses the same authoritative site/proof/facility checks. Passenger ordered scan and station precedence unchanged.

Added `godot/tests/p2_perf_c_n84_construction_site_keys_oracle_20261117.gd`, `run()`: independent old ordered-scan oracle with 2000 sites, missing site, abandoned dock, faction mismatch, invalid receipt, station precedence, passenger path and invalid mission; no site mutation.

TEST EXECUTED: NOT RUN (Godot runtime unavailable in connector execution).
STATUS: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No measured performance claim; only avoids unnecessary O(number of historical sites) keys allocation in construction dock lookups. Frequency/cost of this path unknown.

NEXT: execute targeted oracle, measure source-level N84 construction dock call count and inclusive ms in same-seed paid tick100/600/900; prioritize higher measured N84/ship/dock paths if this site is negligible. Preserve N38, paid cargo and contract parity. No N39/N9/N158 edits; no merge.
