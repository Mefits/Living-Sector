# Living Sector P2 — handoff: second chat N104/N147 passengers + Rust N142 colony navigation (2026-11-14)

## Authority and status

- Integration branch: `integration/godot-phase2-unified-20261113`, shared PR [#249](https://github.com/Mefits/Living-Sector/pull/249).
- Status **SOURCE_WIRED / CODE_UNVERIFIED**. Neither Godot nor GitHub Actions was invoked. Code-level/preload/static comparisons are NOT runtime success.
- One original **N158 TickRunner / N39 World / N9 CreditLedger / N104 ContractBoard / N38 SaveState**; there is no parallel runtime, ghost money/population or instant ship travel.
- The primary developer's N148 lease was respected. The small N39 schema cross-edit was called out publicly in PR coordination before the primary N148 lease was released; other N39/N158 shared changes were made only after its release. Do not overwrite N148 lifecycle/retirement.

## A. Real N104/N126/N147 passenger vertical wired to the canonical tick

1. `godot/scripts/sim/phase2/unified_n104_passenger_transit.gd` **NEW**: N147 source-ready plan -> live faction N9 debit and canonical N104 prepaid passenger escrow; N153 actual-hull and signed offer selection; N81/N84 sequence and genuine N14 fuel/route preflight; N104 accepted / physical embark / physical delivery / escrow payout. Backed by original Rust `sim_server/engine/transactions.rs` and `strategy/colony_development.rs`.
2. `godot/scripts/sim/economy/contract_board.gd`: `_valid_physical_receipt` accepts only exact real passenger receipt and location for passenger type; cargo receipt validation remains unchanged.
3. `godot/scripts/sim/phase2/unified_ship_ai_execution.gd`: former no-op `EmbarkPassengers` and `DeliverPassengers` N84 leaves now require a real N21 dock and emit N146 `RequestShipTransaction` operations `passenger_embark`/`passenger_delivery`, not phantom cargo.
4. `godot/scripts/sim/phase1/n39_native_world_production.gd`: live authority rechecks source N147/N153 decision and commits either the prepaid contract, accepted BT or physical passenger transfer atomically to the existing World/ledger. The actor IDs, wallet totals and domain changes are verified.
5. `godot/scripts/sim/phase2/n158_production_runtime.gd`: faction-cycle N147 prepaid posts and N153 assignment, ship-phase N84/N146 passenger operations, N38 integer-normalized manifest/receipts and read-only summary.
6. `godot/scripts/sim/phase1/n39_native_world_schema.gd`: persisted `passenger_manifests`/`passenger_receipts`, original and destination household proofs, real N9 `passengers/<contract_id>` wallets through transit, in-flight N148 retirement guard; completed history can outlive retired hull. Legacy worlds without these optional records retain validity.
7. Actual population count decreases at embark, increases ONLY on arrival; proportional household wealth is moved by real N9 receipts both ways. No fake passenger goods/market stock changes. N101 paid delivery XP, N148 hoard recovery and ship reputation are preserved.

**Wiring is implemented, execution not tested.** There is no claim of completed passenger contract on clean source seed. N147 only operates between established, inhabited markets: empty clean seed has no second colony.

## B. Critical newly found original Rust N142 navigation/charting step

Source `native/crates/sim_db/src/spawner.rs::chart_colony_routes` is called after `seeder::seed_all` by frozen Rust colony integration. It was missed in the prior N142 seeded-return handoff, which counted only original JSON corridors and declared there were no `*-colony` nodes. The original SQL proves an **additional** empty-colony location/chart step. This is not invented geometry or a new design.

- SQL `INSERT OR IGNORE INTO locations ... SELECT body_id||'-colony','colony' ... WHERE body_type='planet'`.
- SQL `INSERT OR IGNORE INTO travel_routes ... MAX(8,CAST(8+10*ABS(radius1-radius2) AS INTEGER))` for different locations in the SAME system where at least one end is a colony target.
- No synthetic interstellar mesh, no finished facility, no population, no money.
- Independent exact comparison of the eight original frozen `native/priv/galaxy/data/worlds/*.json`: **12 raw directed JSON lanes, 24 existing Rust seeder bi-directional DB lanes, 25 original charted planet navigation addresses and 146 same-system charted directions => 37 nav points, 170 directed original Rust SQL edges**. `earth-station -> mars-colony` cost 18; `pirate-outpost -> earth-station` remains 855 by authored source lanes.

Files: `godot/scripts/sim/phase2/unified_n142_original_colony_chart.gd` **NEW** (pure SQL parity projection), `godot/scripts/sim/route_graph.gd` (native seeded DB projection only), `godot/scripts/sim/ships/native_location_resolver.gd` (real moving body target, NOT a free dock), `godot/scripts/sim/route_graph_audit.gd` (both raw and seeded+charted checks), and NOT RUN tests `godot/tests/n4_registry_routes_check.gd`, `godot/tests/p2_native_seeded_route_parity_check.gd`.

Commits: [N104 original](https://github.com/Mefits/Living-Sector/commit/605bea713d08da9b9080f7808c0019bc17c244de), [N39 Apply](https://github.com/Mefits/Living-Sector/commit/7804194bea81f03a60b52309da030463d0dfdde2), [N158 dispatch](https://github.com/Mefits/Living-Sector/commit/23b522e5b99cd6aa53f0978f0630c20bf4266626), [N104 N148 delivery parity](https://github.com/Mefits/Living-Sector/commit/70f0ebcb1fb5c5b412210821bfe0a56150765e80), [N142 original SQL](https://github.com/Mefits/Living-Sector/commit/1978a1c99ea259c191acbf91c998c9663c6d534f), [route chart insertion](https://github.com/Mefits/Living-Sector/commit/f2643ee0f62c80b5ea6c3c7aae923cafeb8c00f7), [N43 orbit mapping](https://github.com/Mefits/Living-Sector/commit/7470df1dd08ddb29593860d154feb965874b4eb2).

## C. Incomplete — real founding N144/N151 still NOT connected end-to-end

The Rust game `native/crates/sim_core/src/strategy/coordination.rs` is sole authority for the **head decision** `found_colony` or `supply_colony`. Godot N151 currently exposes SOURCE read-only site proposals and `N39.apply_native_colony_foundation(..., head_authorized)`, but N158 does NOT produce/verify that actual head authorization or call the N39 founding method. Do NOT pass `true` based merely on a read-only `N151Founding.scan` proposal.

After actual head approval original Rust `strategy/colony.rs::commission` starts a site at zero monetary debit (NOT a completed colony), then uses prepaid `strategy.colony.v1` passenger contract for 10 or Director-50 existing settlers, real stock and N9 escrow for 3x200 metals, 150 N141 paid shifts and 20,000 N9 real startup credits at finished station.

A second source owner `native/crates/sim_server/src/engine/colony.rs::prepare_docks` creates a **temporary `construction_dock` (without existing market)** at the site to receive real population and cargo. Current Godot N39 schema and N104 move require station-owned market docks and a real target household, so the founding passenger variant must not be labelled functional yet. Need faithfully adapt temporary dock, initial household only when source permits, dock/cargo and N141 labor gate without bypassing one-world ledger. Finish via original N154 construction materialization, not via a ghost market or free population.

Next work should be grouped into one large colony vertical:
1. Authentic N144 head grant from existing N134/director strategy, N39 site approval only when source-authorized.
2. N151 `prepare_docks` existing site -> uninhabited temporary physical dock and applicable schema/traffic support.
3. N144 `strategy.colony.v1` prepaid passenger and metal contracts -> N104 real boarding/transport/unload to source-backed initial colony household; N141 wages and N154 600-metals materialization with 20k real startup debit.
4. N38 restore and one **later** coordinated project-wide Godot test after all original Rust integration, per user instructions.

No balance, UI, concept or frozen Rust files touched. Do not run intermediate GitHub Actions.

## Verification & handoff

- Static source comparison: matched frozen Rust spawner SQL exactly, enumerated original 8 JSON worlds and 170 DB edges; all 12 modified GDScript scripts and tests have import/preload paths present in the latest shared branch tree. **No GDScript parser execution or runtime tests.**
- Remaining concerns: original Rust colony founder with native Director strategy has not yet been wired; origin passenger full-route and N104 physical dock must be included in eventual one coordinated end-to-end run; N142 new 170 graph count changes old 24-count expectations (two tests updated, other coverage later).
- Lease `godot/docs/phase2/leases/20261114-1634-second-chat-n104-passenger-vertical.json` to be **RELEASED** after documenting this handoff.
- Symbolic direction readiness: **~55–60% source integration**, **not validated**. Not readiness for full project and not proof a colony has been founded.
