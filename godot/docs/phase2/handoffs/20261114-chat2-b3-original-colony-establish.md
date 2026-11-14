# Living Sector — Chat №2, Miro B3: actual Rust colony::establish in one N39 World

14 Nov 2026, shared `integration/godot-phase2-unified-20261113`, PR [#249](https://github.com/Mefits/Living-Sector/pull/249), Miro [phase2 board](https://miro.com/app/board/uXjVENhEuiM=/).

**B3 STATUS: SOURCE_WIRED / CODE_UNVERIFIED.** B1 authentic founded site, B2 real N144 passenger/Metals transport, and B3 Rust source establishment are wired through the same N158, N39 World, N9 Ledger, N104 Board and N38 SaveState. NO Godot F5/parse/run/build, NO GitHub Actions, no statement of actual runtime PASS, and no user runtime test requested until all Rust→Godot integration is done.

## Frozen Rust truth

`native/crates/sim_server/src/engine/apply.rs::tick_construction_labor` invokes `engine/colony.rs::establish` only after N141 `labor::work` succeeds during the 5×mult source cadence (including zero worker success if already complete), the site has received **600 physically transported Metals**, and its **150 labor units were actually paid** to residents, not counters granted for free.

`engine/colony.rs::establish` mutates the SAME N151 dock entity at the SAME charted `body-colony` location:
- prior `construction_dock` -> `station`; keeps original ID, negative DB ID, orbit/owner, N21 dock slots and arrived N147 population
- adds market service to facility, upgrades condition=1, preserves last N141 WorkShift reservation
- debits 20,000 credits from current real faction treasury, credits 20,000 to THAT dock's existing wallet; fails with `insufficient_startup_capital` and retains site if it cannot pay
- instantiates first authentic `Market` record for the same dock, id `market-<location>`, 17 `Commodity::ALL` base prices, empty supply, demand Food=5/Water=3, elasticity 0.02, spread 0.10, original `50*mult` order expiry, empty native MarketFlow/History
- destroys ONLY the finished ConstructionSite, writes ColonyEstablished/ConstructionSiteDelete, retains N9/N104/N15/ship/passenger provenance

No new facility, vessel, population, warehouse stock, unbacked treasury credit or parallel tick/World.

## Code changes already committed

1. **`godot/scripts/sim/phase2/unified_n151_colony_establish.gd` NEW**: detached source establishment stages exact dock+market mutation, one prepaid 20k N9 transfer between existing accounts, no phantom actors, copies final N141 worker reservation to existing station, destroys completed site while recording an immutable `n151_colony_established:<id>` proof. It does not self-publish.
   - Source truth checks **immutable original financial/physical history**, not just the numerical site progress: each B2 delivered shipment needs its original N15 source purchase, physical target `construction_site` unload and Board PAID, N9 payout with matching escrow->ship legs; 600 total Metals from real shipments; N141 work must have 150 balanced faction->household salary legs with N9 receipt of same tick; verifies live N151 temporary dock/resident and N9 funds.
   - Commits [21d7e815](https://github.com/Mefits/Living-Sector/commit/21d7e8151347dbad05bf78d56f1c1f9f09fa69c2), [03dacd10](https://github.com/Mefits/Living-Sector/commit/03dacd105cde0650d2360c61d62fc3cbbc8548b6), [318fabcc](https://github.com/Mefits/Living-Sector/commit/318fabcc4c7b0ee5d7a32a21bf2db1d5868322dd).
2. **`godot/scripts/sim/phase2/unified_n151_colony_establish_archive.gd` NEW**: read-only N38 history guard that permits old `colony_dock_prepared` only if it has either the live original approved N151 site or the authentic archive of the completed SAME dock/Market, physical shipments, 150 wages and no resurrected site/material order; verifies original DB id/proof and linked N104 receipts. [760e3fdb](https://github.com/Mefits/Living-Sector/commit/760e3fdb278d1872d169e7a0a64d52f15a99f09c).
3. **`godot/scripts/sim/phase1/n39_native_world_schema.gd`**: a site that Rust `establish` legitimately despawned is no longer rejected as `n151_temporary_dock_missing_live_actors`; instead its archived proof and same changed dock are verified. Every orphan dock and fake history still fails closed. [e1215bd7](https://github.com/Mefits/Living-Sector/commit/e1215bd7ddc341c276a1c661a48fddb9d0abbbf1).
4. **`godot/scripts/sim/phase1/n39_native_world_production.gd`**: replaces permanent `native_N151_colony_establish_required` stub inside **existing** `apply_native_construction_labor`, after REAL successful N141 work. Calls detached B3 stage and atomically publishes only after independently checking unchanged other markets, facilities, households, all ships, N104 Board, old N9 receipts, stable original negative dock ID and sum of N9 accounts; one new Market, one fewer site, one new completion receipt, EXACT 20k CR treasury->existing dock wallet. On insufficient money, records original source `labor.blocked_reason` and retries later, never spawns a free station. Returns factual `established` results distinct from ordinary N154 new facilities. [f38f7c31](https://github.com/Mefits/Living-Sector/commit/f38f7c315b6db6b66925a760cefbb11d83fea119).
5. **`godot/scripts/sim/phase2/n158_production_runtime.gd`**: unchanged sole N158 TickRunner invokes its existing N39 paid N141 shift; B3 happens in that original boundary, not an added independent clock. Adds factual `native_b3_real_colonies_established_this_tick` diagnostic and N38 exact integer JSON restoration of new `delivered_metals`, `paid_labor`, `shipments`, `shifts` completion proof fields. [fe6c545c](https://github.com/Mefits/Living-Sector/commit/fe6c545c11ad9a6b969b1125e85cd6f149187bc8).
6. **`godot/tests/p2_b3_native_colony_establish_check.gd` NEW, NOT RUN**: staged source negative regression: cannot establish imaginary site, cannot invent Market from proposal, uses exact immutable 17 base prices, 5/3 demand, `50*mult` expiry and no N9 credit creation. Does NOT simulate/pass a forged full 600-Metals ship+work path or claim full E2E PASS. [3a235ca4](https://github.com/Mefits/Living-Sector/commit/3a235ca465ff84ba89f92ed1fdc49d69e3eb8da8).

## Verification / limitations

- Static GitHub HEAD audit after changes: all six touched B3 source/test files have balanced quote/bracket structure, valid existing preload paths and terminal newlines. Also individually confirmed N39/N158/Schema integration symbols.
- **No code execution**: Godot parser, simulation, full positive scenario, 3 B2 real shipments + 150 N141 work + B3 establishment + N38 restart remain to be covered in the final coordinated integrated test when the user authorizes gameplay verification; no GitHub Actions invoked.
- Source currently has only frozen seeded native systems; global map/UI presentation of a newly established Market must be assessed in final whole-project F5 integration, not asserted to work here.
- **Scale note:** immutable B3 archive checks reread prior construction receipts for each finished colony at schema-validation time. Semantically fail-closed now, but after very large galaxy expansion may need a one-pass archive index in N39 Schema to avoid O(C×R) validation cost. This is a documented performance opportunity, not a reason to rewrite economy during migration.
- Source B3 is a separate marketless->market transition. In Rust this is the same N151 dock entity, not `N154.materialize_facility` which creates a different station. Do not replace one with the other.
- A positive test cannot be marked PASSED without a real actual N14 ship trip/N21 dock/N15 unload/N104 escrow, genuine N141 N9 wage transfers, actual B3 N9 startup and N38 save/reload.

## Parallel team coordination and next steps

Chat1's `20261114-chat1-n108-real-gate-jump.json` was active while B3 pure source stage and negative test were implemented. B3 avoided N39/N158/Schema until Chat1 explicitly RELEASED N108; only then edited those shared files. No N108 source code was replaced.

B1 + B2 + B3 of Chat #2's **colony/migration vertical** now have source integration handoffs. The next cross-team goal is final Phase2 source audit/synchronization, not unsolicited balancing changes or repeated intermediate Godot tests. Chat #2 should claim another non-overlapping task only after checking live PR HEAD and leases, ideally support final migration scope and historical save consistency.

**This handoff is source-level, NOT a verified gameplay release.** Lease `godot/docs/phase2/leases/20261114-2005-chat2-b3-colony-establish.json` will be RELEASED.
