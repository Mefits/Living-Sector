# Living Sector / P2 — second-chat N144 paid founding passenger commission

Date: 2026-11-14. Shared branch `integration/godot-phase2-unified-20261113`; one PR #249.

## Status and provenance

**SOURCE_WIRED / CODE_UNVERIFIED**. No Godot engine, F5, headless test, Actions or Windows build was run. Static source checks only. This block is **N144 active-site PASSENGER** commission, NOT all of N144 colony expansion and definitely NOT final N154 establishment.

Frozen Rust references:

- `native/crates/sim_core/src/strategy/colony.rs::proposals` active-site branch and `::commission` with `PROJECT_TAG = strategy.colony.v1`.
- `native/crates/sim_core/src/strategy/coordination.rs`: N134 one HeadDecision grant for `supply_colony`, never a project quote alone.
- `native/crates/sim_core/src/strategy/director.rs::retain_or_switch`: retain/superiority 1.20/two-cycle hysteresis from original defaults, not forced immediate expansion.
- `godot/scripts/sim/phase1/n151_native_colony_commission.gd` source lifespan, 800 base, Director `max(800, 100*realDistance+1200)`, paid 80 credits per original settler.
- Actual single N104 `ContractBoard.post` / N9 `CreditLedger.transfer`; N153/N81/N84/N21 already source-wired N104 passenger flight.

## Implemented and wired to ONE game loop

1. **NEW** `godot/scripts/sim/phase2/unified_n144_colony_contracts.gd`:
   - Looks only at real approved unfinished N151 sites, prepared N151 construction_dock and source physical market. No fake actor/route.
   - If original site does not yet have required 10 (non-Director) or 50 (Director) people, validates REAL origin household with spare original 10-resident reserve, faction treasury after payment + source 20,000 startup reserve + uncompleted N141 paid labor + 5,000 floor, real passenger hull, directed N142 route, and no still-active N104 for the same colony.
   - If people have arrived, returns `n144_original_metals_marketless_delivery_pending`, **not** a fictitious Metals contract or phantom Market deposit. In Rust this becomes a 10,000 credit / up to 200 Metals next stage — not completed here.
   - Reuses P1 `N134CoordinationCycle`, `N134Head`, `N134Policy` plus real `N155Director.option_score` and native N113 `retain_or_switch` to get **an actual source HeadDecision** and bounded grant. Builds P1 source enum `Funding` and immutable faction/contract view; the authoritative N39 recomputes approval before committing. Strategic memory lives in the same `research_directors[faction].strategic` owner and survives N38, including pending 2-cycle switch.
   - Stops new colony order when actual `native_planner_records` records N98 planned or N121 active work, and when a funded N104 order is already active.
   - Posts one canonical `passenger` ContractBoard order with original tag `strategy.colony.v1`, source `colony_site_id`, quantity 10 or 50, **payment exactly quantity×80**, a new zero-balance escrow filled by transfer from the REAL N9 faction treasury. No passengers or money created, moved, or settled on posting.
2. `godot/scripts/sim/phase1/n39_native_world_production.gd` new `apply_native_n144_colony_passengers`: independently recomputes current N134 head comparator, N144 site/source and approval, then atomically commits one original Board+Ledger+Director-memory revision. Validates allowed domains, site link, escrow cardinality, existing contract immutability, equal total N9 supply, **exactly one new N9 post receipt**, original money receipts unchanged, exact treasury debit=escrow credit, one canonical account map. Head-only memory cannot touch money.
3. `godot/scripts/sim/phase2/n158_production_runtime.gd`: one original 60×mult N134 strategy cycle consults N144 after existing N111/N134 source comparison and **before** N100/N154 alternative commissions. If an actual colony Passenger is prepaid, it is exclusive for that head cycle (no duplicate build/HTN). A contrary source N113 head decision can preempt an otherwise conflicting legacy N154 grant. Read-only last result and counts provided. N38 normalizes the N113 `since`, `pending.consecutive_cycles`, and `pending.first_seen_tick` JSON fields; diagnostics cleared on checkpoint restore.
4. `godot/scripts/sim/phase2/unified_n104_passenger_transit.gd` N153 passenger ship selection now recognizes the **real** site-approved marketless temporary N151 dock only for `strategy.colony.v1`, while ordinary passenger migration still requires TWO physical markets. N84/N21/N104 boarding, actual flight and landing remain performed by the existing canonical N39/N158 physical execution; this block does not bypass travel or invent residents.
5. `godot/scripts/sim/phase1/n39_native_world_schema.gd`: validates optional Director N113 memory and N144 contract typed provenance, exact paid quote, payer/faction and active site identity while current. Historic PAID/EXPIRED contracts may outlive later completed site. Rejects manufactured marketless contracts.
6. **NEW** `godot/tests/p2_n144_paid_colony_passengers_source_check.gd` (NOT RUN): frozen source Sol fixture with explicit TEST-ONLY orbital habitats + approved N151 site+prepared zero dock, checks quote, marketless N104 post, exact N9 ledger delta and escrow, no person/ship/market mutations, duplicate replay rejection and no mint. Test is source-only, not proof of live Head vote/flight.

Major commits:

- [N144 source plan + original head and paid order](https://github.com/Mefits/Living-Sector/commit/5629dd4943bad756ab71192b15822f935b3b5559)
- [single N39 apply](https://github.com/Mefits/Living-Sector/commit/355dcbd0da661d005f8dbbe3e4626221c1c90ff2)
- [single N158 strategic N144 call](https://github.com/Mefits/Living-Sector/commit/57b78bf844a466bbec4bbef4d0ddc603562d20b6)
- [real N153 marketless destination selection](https://github.com/Mefits/Living-Sector/commit/7c6df638be013f8b6b4af308fe0fd11c043bc944)
- [N113 memory and N144 contract Schema](https://github.com/Mefits/Living-Sector/commit/47abb946f75234fb1ed534480627166f94ea30c7)
- [N38 persistent hysteresis](https://github.com/Mefits/Living-Sector/commit/5a2beb744e06d4eab5038d6246b47c2c86caeb01)
- [no competing N154 grant](https://github.com/Mefits/Living-Sector/commit/bd3ed54f1af855513e796e9522b89d11aed55c62)
- [N144 test added, not run](https://github.com/Mefits/Living-Sector/commit/fad3524efe3055cf33f94f7e02a1d41a3e331efb)
- [source scoring and source enum normalization](https://github.com/Mefits/Living-Sector/commit/9e6fb3775093d5fec09de20e9352fd87d982160b), [correct source strategy/funded commitment](https://github.com/Mefits/Living-Sector/commit/347e43561cea6a81f7e6e308e44a4a1d70a7e841)
- [exact N9 prepaid receipt proof](https://github.com/Mefits/Living-Sector/commit/251c7045a5b868b363d21153a232be6eab4e6245)

## Verified static / unverified live

Readback/static balanced brackets/string scope/import paths/NUL/final newline **PASS** for the 6 touched scripts and new test at PR HEAD `bd3ed54f1af855513e796e9522b89d11aed55c62`; all `preload` source paths exist. These checks were repeated after later commits, before the final N9 receipt adjustment. No GDScript parser, execution or actual passenger trip was run. A future final coordinated Godot pass MUST execute the test, exercise N113/N134 Director elections with real profile and current markets, real N153 selection, N14 physical route, N21 dock, N104 embark/disembark/payout, N38 midflight reload, and reject duplicate N9 posts. Until then NO PASS statement.

## Still missing (do not misrepresent as closed)

- **N144 new `found_colony` head grant** from actual Rust colony::proposals / Director decision to the existing source `N39.apply_native_colony_foundation`. Only previously N151-approved sites can use this N144 paid passenger block; clean seed does **not** autonomously found one from these changes alone.
- Next original **N144 materials**: marketless physical 200-Metals N15 unload per paid shipment → one N154 `ConstructionSite.progress_delivered` receipt, repeated until 600. Existing N97 cargo uses Market; do NOT fake a market or transfer stock by changing counts without physical N15.
- **N154 establish**: once 600 metals + 150 actual N141 shifts and other Rust gates succeed, convert SAME temporary dock to station, create real market and debit original 20,000 from faction treasury to dock N9 account. Preserve paid contract history while retiring the original active site and updating N38/source actor links.
- Full original colony development/aftercare supply, facilities, migration, and final runtime acceptance also pending in the overall migration.

No balance/UI/new content/Actions changed. No new PR or branch. N150 ship-memory parallel worker owns unrelated ship-price code and its separate N39/N158/Schema sections; do not overwrite. Lease `godot/docs/phase2/leases/20261114-1751-second-chat-n144-paid-colony-contracts.json` will be released with this handoff.

**Symbolic direction completeness: ~73–77% of source-code integration, NOT verified.**
