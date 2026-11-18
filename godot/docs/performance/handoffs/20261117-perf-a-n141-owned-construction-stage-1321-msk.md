# PERF A — N141 construction owned stage (2026-11-17 13:21 MSK)

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262. No merge.

- CODE `e5bb38b9c2fd17d89940c00d089be59ac2df6b97`: N39 `apply_native_construction_labor` replaces `_copy_world("L2671", true)` with detached root and deep copies of seven explicitly mutable domains: construction_sites, construction_receipts, construction_contracts, populations, faction_treasuries, facilities, markets. Scalar construction_next_db_id remains root-local. Read-only ships, contract_board, cargo_receipts and other domains are shared only for reads.
- TEST `0e767c86482c9a70a83865cfedd900bc62d16269`: `godot/tests/p2_perf_a_n141_construction_owned_stage.gd`; deep World oracle, rollback/source unchanged, nested mutable-alias negative.
- Source review: `NativeConstructionLabor.paid_shift` reads ship/BT, facilities, research_directors and builds detached site/household state. N154 materialization mutates construction/facilities/treasury/receipt domains; B3 colony stage performs its own `world.duplicate(true)` before writes, then returns a detached proposed world. Full Schema.validate and N9 account oracle remain enabled.
- Status: CODE_COMMITTED, CODE_UNVERIFIED, TEST_ADDED_NOT_RUN. No Godot runtime/CI executed in this shift; no CPU/p95 speedup claim. Existing CI #43972442164 predates this code.
- Risk: new owned-domain boundary must be checked with real N141 paid shift, B3 colony establishment, N154 materialization, rejection and N38 restart. Strict same-seed parity (N9/N39/N38/BT/RNG/cargo/contracts), early/late CPU ms/paid tick and p95 required before acceptance.
- Next: targeted N141 test plus real paid construction/colony fixture, then coordinated <12min CI checkpoint with other workers. Continue profiling actual frequent N39 copy sites; do not duplicate N9 WeakRef, N158 projections or earlier L196.
