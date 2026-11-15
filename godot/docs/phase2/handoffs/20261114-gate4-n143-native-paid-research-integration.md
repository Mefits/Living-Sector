# Living Sector P2 Gate4 — canonical faction treasury + N143 native paid research
14 November 2026. Shared branch `integration/godot-phase2-unified-20261113` and Draft PR #249. Scope: ONE large research block; no manual controls or invented tech.

## Implemented and actually executed
- Project `n158_galaxy_production_seed.gd` imports **original frozen** `native/priv/galaxy/data/factions.json` treasury values (3 x 240000 CR) as `world.faction_treasuries`, maps them into the one **N9 ledger** using `Schema.faction_account`. Never synthesize a second treasury or silently fund an older save.
- Seeds N155 source `profile_from_personality`, one research head per real faction; `world.research` remains the original authoritative researched-tech list, `world.research_directors` holds science progress/target/history; `world.research_receipts` stores actual shift proof. Only frozen N82 catalogue technologies can be unlocked.
- New `unified_native_research_phase.gd` constructs N155 observation + N143 `observe_research` / `prepare_paid_shift` over **actual** N39 markets, faction balances, households and same-tick N39 facility employee occupancy. No pretend local electronics, free workers, arbitrary extra technologies or money.
- `N39.apply_native_research_phase` stages all N143 proposals into a detached world + cloned existing ledger, performs a **single-world/ledger atomic Apply**: N9 faction pays (source ceil electronics quote + 10CR), station receives input payment, existing household receives wages, real station market loses 1 electronics, N143 work progresses by 10 with exact receipt and only then can source tech unlock. `N143Shift.verify_authoritative_receipt` checks original source intent and internal trusted N9 commit. All three wallets and total credits revalidated before publishing state. Duplicate tick/receipt refused by source.
- N158 `factions` phase runs after N150 market and N153 ship contracts with the SAME source clock and N9 authority; `economy_summary` and read-only `observer_panel.gd` show treasury, technology progress, completed tech and actual payments.
- N38 JSON restore normalizes research-head counters, last paid shift worker counts and N9 receipts (not f32 research profile rounding), verifies correct immutable N9 balances and matching paid research receipt IDs. Previous saves **without** all three source-faction research fields remain valid without minting missing treasury on restore, but they do NOT retroactively acquire new research; a future explicit migration must decide whether to seed those source accounts, or use a new game for a functioning N143 world.

## One real Godot CI acceptance — PASS
- Workflow: `.github/workflows/p2-unified-godot-smoke.yml`, **Godot 4.7.2** on GitHub Actions.
- GitHub Actions **[run #43515148008](https://github.com/Mefits/Living-Sector/actions/runs/43515148008)** SUCCESS: editor import 0, compile-all 0, existing N158 economy 0, new Gate4 research 0. Verified exact log:
  `P2_CI_RESULT editor=0 parse=0 economy=0 research=0`
  `P2_GATE4_ORIGINAL_N143_PAID_RESEARCH_N9_SAVE_PASS`
  `P2_UNIFIED_ECONOMY_ACCEPTANCE_PASS`
- Test `godot/tests/p2_gate4_native_paid_research_check.gd` uses original source 8 systems / 3 factions and 240000 CR per faction, checks insufficient-funds refusal, 3 real paid N143 shifts, N9 money conservation, durable receipts and research progress, replay rejection, N38 disk save/reload and further native technology unlocking. No fictitious station/workers/tech fixture.
- Previous run #43514818543 surfaced outdated older 5-phase-only test and direct dictionary comparison of float-science profile across JSON; both were corrected, with strict finance/tech/progress assertions retained. Only TWO CI runs, not recurring micro-tests.
- NOTE: runner logs still include preexisting nonfatal `Unicode parsing error ... Unexpected NUL character` warnings despite parser exit 0, not investigated in this block; do not describe parser as warning-free.

## What remains for full Rust→Godot integration
- **Next major Gate4 slice:** N141/N154 physical construction, shipyards and colony site materialization funded by the new real faction N9 accounts; require N104 real material delivery and N141 paid workforce. Source-only N147 migration and N143 long-term replan are separate incomplete goals.
- Gate5 full faction head/administrators/Hybrid Planner, diplomacy, crisis execution and better policy integration remain. No manual fleet UI.
- No long-duration multi-year all-systems run; source N143 paid loop and disk restore have been proven by CI, not total-game completion.
- Preserve one N39 World, one N9 Ledger, one N104 Board, one clock, one N38 SaveState. Do not add new gameplay/balance or dozens of test PRs.
