# Living Sector P2 — N151 original temporary colony dock and zero-resident housing (second chat, 14 Nov 2026)

**Shared PR:** #249, branch `integration/godot-phase2-unified-20261113`.

**Status:** **SOURCE_WIRED / CODE_UNVERIFIED**. No Godot runtime, parser, Windows build or GitHub Actions was executed. This is source integration, NOT evidence of colony completion or a PASS on P2 area B.

## Frozen Rust source and canonical ownership

`native/crates/sim_server/src/engine/colony.rs::prepare_docks` is called for an AUTHORIZED unfinished `ConstructionSite` with `labor.colony_source` after the Rust spawner has charted the target as a physical navigation location. Original Rust creates:

- A **temporary `construction_dock`**, id `facility-<location>-<site-name-slug>`, **four** N21 docking slots, 0 credits, 0 crew, condition 1.0, reputation 50, no market/service inventory.
- A resident household, id `pop-residents-<location>`, **zero** people, **zero** wealth, consumption Food=1/Water=0.6, growth 0, baseline source sentiment.
- The same new negative constructed DB id for dock and household, alongside a durable site-to-actor record. These are zero-valued real actor wallets inside the original **N9**, NOT funds or new settlers.

No colony station or Market is created; that occurs only in **`engine/colony.rs::establish`** after real physical settlers/materials/labor and 20,000 startup treasury transfer. Do not shortcut it.

## Implemented / actually connected source slice

1. **New source adapter** `godot/scripts/sim/phase2/unified_n151_colony_dock_phase.gd` ports `prepare_docks` into a pure staged proposal for ONLY approved live N151 site+receipt with existing N142 physical graph. It derives stable source ids, reserves the original monotonically decreasing `construction_next_db_id`, and adds one dock+0-head household per site. A legitimate pre-N154 save without the construction domain remains a no-op. Replays create no further actors.
2. **Single N39 World/one N9** `n39_native_world_production.gd::apply_native_colony_prepare_docks` reevaluates source site, rejects unrelated World changes, appends exactly TWO zero-balance accounts per new dock, validates Schema/account totals, and atomically publishes the real actors. There is no N104 or ledger clone retained after commit.
3. **N158 source faction phase** invokes N39 dock preparation only after original N151 scan, using its existing N142 seeded-and-charted physical graph, persisting in the SAME N38 snapshot.
4. **N39 Schema** permits marketless `construction_dock` and its temporary household ONLY when their origin, faction, site, negative DB id and original `colony_dock_prepared` receipt match. An arbitrary non-market facility or household cannot bypass this. Construction receipts and source zero-asset history cannot be forged without breaking schema.
5. **N156 / N130** `unified_facility_lifecycle_phase.gd` and `unified_service_restock_phase.gd` process the real dock lifecycle without inventing a seller or failing the whole tick merely because the original temporary port has no market; service purchase is skipped when no source Market exists.
6. **Real N21** `unified_fleet_logistics.gd` can reserve a temporary `construction_dock` type only on a live same-faction original site, no market warehouse registration. N39 `apply_fleet_logistics` authorizes physical dock only for an assigned original founding **N104 passenger** or **N91 engineer** BT; undock remains a real reservation release.
7. **N84 / N146 / N104** `unified_ship_ai_execution.gd` selects the exact site-linked prepared destination dock for `strategy.colony.v1` passengers and original N91 construction engineers, while regular commercial contracts still target actual Market stations. N158 dispatches the authentic requested N21 dock type. `unified_n104_passenger_transit.gd` validates founder-specific real N21 destination dock and transfers actual population+carried N9 wealth to the source-created initially zero household; all other passenger/commodity types still require a regular Market.
8. **N38** normalization of new source receipt integers `native_db_id`, `credits`, `population_count` and zero household's negative native db id is added to the existing one-save restore only. Never synthesizes restored residents or money.
9. **New NOT RUN regression** `godot/tests/p2_n151_original_temporary_dock_check.gd` uses original Galaxy data + actual N142 graph, test-only tech authorization and N39 site creation; asserts exactly 1 original dock, 1 zero household, no destination Market, unchanged money supply, replay idempotency, N38 restored actors and rejection of forged household. Not an in-game source N134 grant nor a validated game run.

### Changes / notable commits

- [N151 source prepare_docks adapter](https://github.com/Mefits/Living-Sector/commit/f972c1054a9ed0a1d9cf9bb6b3fc9225e8cddb4e)
- [N39 source actor and N9 commit](https://github.com/Mefits/Living-Sector/commit/aae66f8956fd3813e233ad95c08978d069655da5)
- [N39 marketless dock/household invariants](https://github.com/Mefits/Living-Sector/commit/763e7cc82594de784f3b5304fe396b4ecb47064f)
- [N158 live prepare_docks phase call](https://github.com/Mefits/Living-Sector/commit/ce9e5ab3cb663bea6caddbb2db0236c67bb64e85)
- [N156/N130 genuine marketless lifecycle](https://github.com/Mefits/Living-Sector/commit/2b1abd993b43f24397aae5280f018088283815b2), [restock skip](https://github.com/Mefits/Living-Sector/commit/10c09ab83a9165be61fbe7314c02c8dd85ae0efd)
- [N21 source colony dock type](https://github.com/Mefits/Living-Sector/commit/b55d9bee547a621e3a598684cbdd0b2777d1ecd2), [N39 physical docking authorization](https://github.com/Mefits/Living-Sector/commit/bae4ffbecb74ce7db67b1bc81ba7c2f9a3823a77)
- [N84 passenger dock choice](https://github.com/Mefits/Living-Sector/commit/3ed009f20d52a2e9b5f17ba0468e5e7e4eefde8c), [N104 landing into actual empty home](https://github.com/Mefits/Living-Sector/commit/1fb541a449f92e928ea824752ceac298a427b269), [N91 engineer dock](https://github.com/Mefits/Living-Sector/commit/59ff7c3e396dfdeb4f9cc2430f8d56e4dc225f74)
- [N158 source dock routing](https://github.com/Mefits/Living-Sector/commit/db468572939931d5981a014f4d5de8727f46e148), [N38 numerical normalization](https://github.com/Mefits/Living-Sector/commit/60f69a6dda6c79143465eb60d53b494160a7d6b4)
- [One end-to-end source regression (added, not executed)](https://github.com/Mefits/Living-Sector/commit/3b4cd0251a13b2c468789d4dde5a1600c96c8ec9), [legacy-save source stage behavior](https://github.com/Mefits/Living-Sector/commit/8b691d22b45df9ab88335cbadf7f28830827f8cf)

## Verification performed, and explicit limitations

- Independent code readback/static balanced brackets, no missing `preload` paths, no trailing whitespace and final newline in all **10 affected GDScripts/tests** at shared PR head `a41c8a860e557b091a44e22a763dad7c3c7ff3c2`. **No Godot parser/runtime test**.
- Source counterparty N149 primary developer is concurrently working on crew N39/N158/Schema with **active lease** `20261114-interactive-n149-crew-live-runtime.json`. They explicitly noted the separate N151 scope. Do **not** overwrite N149 additions. Our preceding N39 write collided once with a branch-head move; GitHub rejected that last shared edit; no unmerged local patch was forced. Compatibility with old N38 worlds was completed in the independent N151 adapter instead.
- Still **NOT WIRED**: the source `coordination.rs` N134/N144 `found_colony` head grant into `N39.apply_native_colony_foundation` in live N158. Therefore a clean seed does not autonomously create a colony by these changes alone.
- Still **NOT WIRED**: `strategy.colony.v1` N144 prepaid 10/Director-50 passenger order and founding cargo contracts for real 3x200 Metals. Source N151 prepares the destination actors, but does not initiate or fake transport itself.
- Still **NOT WIRED**: N97/N15 physical **construction cargo** delivery to a marketless dock. Current canonical construction delivery only supports a Market warehouse, and N39 site schema allows zero physical delivery progress for an unmarketed site. Must change this only in a coordinated future colony-material delivery block, NOT by minting source stock.
- Still **NOT WIRED**: `engine/colony.rs::establish` converting the *same* temporary dock into a station, adding a true market after completion, debiting exactly 20,000 N9 treasury, removing site and persisting native lifecycle; current `colony_dock_prepared` receipt/schema links to an active site and must be transitioned/archived in that final atomic commit. DO NOT claim colony materialization success from this code alone.
- Subsequent P2-wide Godot parser/run, final Rust parity and N38 save/load remain unverified per user freeze. No new UI/balance/ship/technology, no intermediate Actions.

**Direction readiness (symbolic source-code integration only): about 65–70%.** Not percentage of verified functionality. Key remaining large unit is N144 head/funded founding convoy + N154 true colony establishment.

**Lease:** `godot/docs/phase2/leases/20261114-1720-second-chat-n151-colony-dock-household.json` released after handoff.
