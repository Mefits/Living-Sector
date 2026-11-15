# Living Sector P2 — Miro Chat 2 / Б1: real N134/N144 found_colony

**14 Nov 2026 · source-wire only, not game-runtime validated.** Shared branch `integration/godot-phase2-unified-20261113`, PR #249. Board: https://miro.com/app/board/uXjVENhEuiM=/, B1 "Решение основать колонию".

## Finished code path

Original Rust `native/crates/sim_core/src/strategy/colony.rs::proposals` NEW-SITE branch (existing-site passenger funding already connected by previous chat2 work) is now wired to `coordination.rs` native one `HeadDecision.selected_option=found_colony` and the existing single N39 World, not an unauthorized read-only N151 scan:

1. **New pure selection** `godot/scripts/sim/phase2/unified_n144_new_colony_head.gd`. Iterates ONLY existing actual Rust body IDs and owned original Market/Station ports, avoids all occupied or already commissioned planetary sites. Calls existing `unified_n151_colony_founding_phase.gd::proposal` for source capability/eligibility (N142 original chart, real orbit, original research `orbital_habitats`, 600 local available Metals, real solvency, passenger ship/carrier/builder) and scores viable options by original `(0.1+max(ore,ice,gas)+gas*(0.55 when local Gas < 50, else 0.1)) * (4 if own station in system else 1)/(1+real_shortest_distance)`. Stable lexical tie; no injected planets/routes.
2. **Original head approval** `godot/scripts/sim/phase2/unified_n144_colony_contracts.gd::approval` now supports both exact frozen N134 actions: new site `found_colony` if `plan.site_id=null`, existing site `supply_colony`. Reuses earlier real N155 option-score/N113 hysteresis and N134Cycle & N134Head source grants; does not allow a caller-provided `head_authorized=true` as proof.
3. **One N39 authority** `godot/scripts/sim/phase1/n39_native_world_production.gd::apply_native_n144_found_colony`: independently recomputes LIVE N134 base comparison, chooses exact same source N144 candidate and Head grant, then ONLY on authorization atomically appends one N151 original unbuilt `ConstructionSite` and `n151_colony_approved:<site>` receipt. Source actor ID `site-station-<dest>-<tick>`, 600 required Metals, 0 delivered, 150 shifts required and 0 completed. The original N113 strategic memory/pending confirmation is in the SAME `research_directors[faction]` under ONE N38 snapshot. Actual N9 Ledger is unchanged and checked; NO station, Market, household, ship, Metals, personnel or money is created by this grant. Staging validates Schema and allowed domains/actor counts before one commit, no alternative World or timer.
4. **One active N158 strategic loop** `godot/scripts/sim/phase2/n158_production_runtime.gd`: at original 60×tick-multiplier faction head cycle, before existing N144 paid passenger and N154 industry grants, invokes the B1 canonical real source grant. A new approved site preempts duplicate N144/N100/N154 head commitments this cycle; source N151 `prepare_docks` runs LATER IN THAT SAME NORMAL faction tick to create the original 0-person temporary dock. If the original leader votes research/wait instead, don't fabricate a new site, and respect the real strategic vote over competing legacy N154 grant. Source B1 summaries are read-only N158 diagnostics; N38 persistence already supports N113 memory.
5. **Regression source fixture, NOT RUN:** `godot/tests/p2_b1_n144_found_colony_source_check.gd` from original Galaxy data and N142 original routes. TEST-ONLY detached orbital_habitats research and high-expansion personality, not gameplay grants. Asserts actual N134 `found_colony` grant, exact N39 site identity, 0 delivered Metals, no new Market/facility/population/ship/money, no repeat site, one N38 roundtrip. Not evidence of F5/gameplay PASS.

### Code commits

- [B1 original body/route/resource ranking](https://github.com/Mefits/Living-Sector/commit/b049cfc582586b688176fcd72c882d00d388c537)
- [N113/N134 original action for new vs existing site](https://github.com/Mefits/Living-Sector/commit/2a58e56e5b917ddcb59f8da4edfa4fb9c8cb325a)
- [B1 atomic N39 source-approved founding Apply](https://github.com/Mefits/Living-Sector/commit/933e746868a475ee7bb829ef457d17679b730a50)
- [B1 N158 real head-phase call](https://github.com/Mefits/Living-Sector/commit/c55dc2cb5fe6cb81f98d4314970389802c43482a)
- [B1 source regression added, NOT RUN](https://github.com/Mefits/Living-Sector/commit/4f4908db53325c9838be5c4a219ef934a8e371c3)

## Verification and honest blockers

Source files read back from PR; `preload` paths exist and static balanced brackets/string boundaries check found no structural issues for B1 new code, N39, N158, existing N144 shared bridge and new test. **NO Godot parser, F5, headless test, Actions, Windows EXE or true simulation tests run**; remains `SOURCE_WIRED / CODE_UNVERIFIED`. No intermediate CI, balance, UI or concept changes.

- Original Rust can consider remote interstellar candidate ports when physical capability allows. Current pre-existing N151 source adapter deliberately disallows cross-system founding until the N14/N142 long-route expedition can be proven; this B1 code preserves that no-phantom-route guard. **Full source parity pending for distant founding**.
- Frozen source eligibility and decision can return no real affordable candidate on clean data; this is NOT a need to grant free ships, research, money or Metals. If no authorized candidate, N158 creates NO colony.
- The original strategy also has cross-faction diplomacy/security and cargo valuations; no new unverified relation assumptions were added.
- **Miro Б2 open:** N144 real 3×200 Metals shipments, physical N15 unloading at a marketless temporary N151 construction_dock, paid N104/N9 receipts. N144 paid-passenger part is code-wired but not runtime checked.
- **Miro Б3 open:** N141 completed paid shifts and N154 materialization of the SAME temporary dock into real station/Market, original 20k treasury startup debit and correct N38 source history.
- **Miro Б4 open:** real shipyard/colony-development dependencies and source completion checks (don't mint replacement ships).

Last PR HEAD observed after our B1 commits had concurrent Chat1 N83/N90/N97 trade changes and Chat3 source crisis warning; they do not touch the B1 new adapter or the B1 methods. Chat2 lease `godot/docs/phase2/leases/20261114-1857-chat2-b1-found-colony.json` released on handoff. When user says **«Продолжай»**, next owned block is **Б2: actual marketless paid Metals unloading into N151 ConstructionSite via existing N14/N21/N15/N104/N9**. Do not start B3 until B2 has an actual source bridge; avoid unrelated Chat1 ship trade and Chat3 high-level N158/Schema domains.

**No arbitrary percentage of validated game runtime is claimed.**
