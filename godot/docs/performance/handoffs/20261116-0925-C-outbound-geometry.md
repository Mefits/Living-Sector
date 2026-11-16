# PERF C handoff — 2026-11-16 09:25 MSK

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

CODE COMMITS: `065fee79972ad1133ac919b5a47a71e747b01d64`, `b303bdb83b7d3837cd08d8d51f834d66051ac283`, `1b378992c9433b0ed84e2b886263c5da3a416eef`
TEST COMMITS: `de2b7d77ee6288dd55bd7e64a4a3ac05694c95b6`, `f8976c075a5a241ab98841a3452d14c7a67dfb2f`

Files:
- `godot/scripts/sim/phase2/n153_ship_eligibility_index.gd`: within one N153 proposal and one source/destination index, compute outbound per-edge world geometry once and reuse its scalar rows across different ship locations. Inbound geometry stays individual. Maintain inbound-before-outbound steps, missing-position sentinel, and the original _ready_ship fuel/geometry validation priority. No persistent cache, no new World or Ledger.
- `godot/tests/p2_perf_c_n153_offer_route_index_oracle.gd`: adapt cache cardinality and add per-ship step-array mutation negative regression; fix escaped newline comment that previously swallowed at_source assertions.

TEST EXECUTED: NOT RUN (Godot unavailable); CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. GitHub Actions not triggered. No TPS/FPS improvement measured. Source-only verification: all referenced helpers/preloads already exist; existing N153 signatures unchanged.

Mutable-alias protection: outbound scalar rows are deep-copied on append into each ship's steps Array; the negative oracle mutates a nested distance dictionary and checks the cached outbound row is unchanged. Runtime proof still pending.

NEXT: execute N153 oracle in Godot, compare original vs optimized paid-contract decisions/fuel/cargo/order and N38 restart; profile ship-bid geometry at 24/100/500 ships before further indexes.
