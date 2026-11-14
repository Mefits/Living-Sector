# P2 N147 — source colony migration policy bridge (14 Nov 2026)

**Branch:** `integration/godot-phase2-unified-20261113`; [PR #249](https://github.com/Mefits/Living-Sector/pull/249). Starting HEAD `03b34dd`.

## Actual code added
1. `unified_n147_colony_migration_observer.gd`: source N92 colony observations from ONE N39 physical World (stations/facilities, exact resident consumption coefficients, unique live markets, Food/Water reserves, N104 outstanding passenger statuses). Source N147 planner/commission reused, not reimplemented.
2. One source N9 faction treasury and N104 board read-only projection; source N46 class-specific passenger seats, real ship state, original directed N4/N142 path and N14/N43 physical per-leg fuel preflight. No invented destinations, wallets, transport, passengers or supplies.
3. N147 only reports `N147_PREPARED_NOT_POSTED` for source-funded eligible migration after rechecking source households, same-faction passenger ship and budget. Ready is **not** a new contract; `posted=[]` by design until the actual physical N104 passenger executor exists.
4. `n158_production_runtime.gd`: N147 read-only scan on tick 1 and then N134 strategic cadence (60 * native multiplier), retaining the last scan in `economy_summary` and `last_native_colony_migration()`. The scan cannot change current N39 World or N9 Ledger.
5. `observer_panel.gd`: compact truthful state, zero existing colonies vs unposted proposals clearly distinguished; no manual fleet UI or new galaxy control.
6. `p2_n147_colony_migration_policy_check.gd`: frozen real seed must have no fabricated colonies and unchanged checkpoint. Separate **detached synthetic future-colony fixture** validates source N92 -> N147 20 travellers / 1600 CR and refuses missing directed route, insufficient real treasury or life-support stock. It does **not** claim a paid in-game arrival.

## Validation and hard blockers
- Targeted static bracket/string/preload checks PASS on 4 changed/new GDScript files; GitHub re-read confirms all preloads exist, no NUL or mixed tab/space indentation. **Godot executable unavailable; NO parser/headless/F5 executed; GitHub Actions=0. CODE_WIRED_STATIC_PASS, NOT VERIFIED.**
- This is **NOT FULL N147 COLONIZATION**. Frozen world has 3 founding station markets, 0 established colony locations, no N151 colony dock/location creation in the unified N39 schema/registry, and no physical N104 passenger embark/disembark/paid settlement in P2. The source proposal is consequently empty at clean boot.
- For next actual large block implement authoritative N144/N151 colony project `ConstructionSite -> construction_dock + 0-person Pop -> real source route/settlement` with evolving registry; then actual funded N104 Passenger Contract escrow, N48/N104 embark+N14 transit+disembark and N9 one-time settlement. Preserve unmodified Rust meaning; no free facilities or people.
- Existing direct per-item ship buttons remain hidden. No balance tuning or change to original Rust 0.6.7 source. No new GitHub Actions.
