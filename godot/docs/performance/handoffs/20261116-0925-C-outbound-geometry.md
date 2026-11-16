# PERF C handoff — 2026-11-16 09:25 MSK

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

CODE COMMIT: `065fee79972ad1133ac919b5a47a71e747b01d64`
TEST COMMIT: `de2b7d77ee6288dd55bd7e64a4a3ac05694c95b6`

Files:
- `godot/scripts/sim/phase2/n153_ship_eligibility_index.gd`: within one N153 proposal and one source/destination index, compute outbound per-edge world geometry once and reuse its scalar rows across different ship locations. Inbound geometry stays individual. Maintain inbound-before-outbound steps, missing-position sentinel, and the original _ready_ship fuel/geometry validation priority. No persistent cache, no new World or Ledger.
- `godot/tests/p2_perf_c_n153_offer_route_index_oracle.gd`: adapt cache cardinality and add per-ship step-array mutation negative regression; fix escaped newline comment that previously swallowed at_source assertions.

TEST EXECUTED: NOT RUN (Godot unavailable); CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. GitHub Actions not triggered. No TPS/FPS improvement measured. Source-only verification: all referenced helpers/preloads already exist; existing N153 signatures unchanged.

Risk: GDScript Array.append_array copies elements by reference. Cached outbound rows are dictionaries, so modifying a nested step dictionary in a consumer could alias across ship bids; current _ready_ship only reads rows. Test deliberately replaces an Array element (not a nested dictionary). Before accepting broader mutation callers, either deep-copy cached outbound row dictionaries or guarantee read-only boundary with additional oracle.

NEXT: execute N153 oracle in Godot, compare original vs optimized paid-contract decisions/fuel/cargo/order and N38 restart; profile ship-bid geometry at 24/100/500 ships before further indexes.
