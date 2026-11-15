# Living Sector — official GUT + clean-seed autonomous World test

**Date:** 2026-11-15  
**PR:** [#249](https://github.com/Mefits/Living-Sector/pull/249), branch `integration/godot-phase2-unified-20261113`.  
**Exact checked commit:** `e556cccf7f803258abbc9d5a54cdb9c30d0d8700`  
**Runtime proof:** [GitHub Actions #43647250102](https://github.com/Mefits/Living-Sector/actions/runs/43647250102) — **SUCCESS**. Uploaded artifact `living-sector-autonomy-evidence` contains GUT/editor/clean-world logs and `report.json`.  
**Lease:** `godot/docs/phase2/leases/20261115-gut-autonomous-world-test.json` → RELEASED after handoff.

## User decision — important

**The player has no role in current gameplay.** Research/economic player mandates, Hold/Advise/Delegate and player commands are not acceptance requirements. Only real autonomous faction/world evolution is relevant. Do not spend this macroblock on mandate integration.

## What was added, and why

1. Official [GUT 9.7.1](https://github.com/bitwes/Gut/releases/tag/v9.7.1) pinned to MIT upstream commit `aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605`, tested against **Godot 4.7.2**. `godot/testing/gut/install-gut.ps1` and `install-gut.sh` fetch official upstream `addons/gut` in full. Never approximate the library or vendor its 259 files. `godot/.gitignore` excludes local `addons/gut/` and `tests/gut/`. Neither project startup nor ordinary parser/compile is dependent on an uninstalled GUT class.
2. Two versioned **real GDScript** unit-spec templates in `godot/testing/gut/specs/test_*.gd.txt`. Installer materializes them to `godot/tests/gut/test_*.gd` only once the real plugin exists. Source:
   - N84 BehaviorTree serialized cursor, one leaf per tick, bad status rejects fake command;
   - N9 Ledger transfer/replay/insufficient funds/no mint; N38 refuses counterfeit credit and altered physical inventory.
3. `godot/testing/gut/run-gut.cmd` executes official Windows Godot headless import+GUT CLI. `run-autonomy.cmd` runs headless clean world with configurable ticks and JSON report. Full usage in `godot/docs/TESTING_AUTONOMOUS_WORLD_RU.md`.
4. New `godot/tests/p2_autonomous_world_observer_check.gd`: **original unmodified seed**, no custom deficit/stock, no artificial money, ships or contracts; no player orders or mandates. Advances authoritative N158/N39/N9 one tick at a time, validates canonical N39 Schema and equality of N9 account balances at sampled ticks, checks N9 receipt monotonicity, outputs timestamped World KPIs to JSON. Tracks actual physical market supply snapshots, N104 status, cargo/dock receipts, facilities, populations, research, memory and elapsed runtime.
5. New **separate** `.github/workflows/godot-autonomy-gut.yml`: initial installation smoke on adding the workflow, then `workflow_dispatch` for deliberate repeat. Runs the official Godot 4.7.2, pinned GUT and no-player clean world and uploads evidence. Optional `strict_delivery` runs pre-existing genuine 6000-tick paid delivery/restart scenario. The default 420-tick test is **not** advertised as freight PASS.
6. Updated `godot/docs/GODOT_TOOLING_DECISIONS_RU.md` to link actual tooling and CI proof.

## Real Godot 4.7.2 results, not source-only

Run **43647250102**:
- Official Godot installation and editor import: **PASS**
- Installed GUT pinned 9.7.1: **PASS**
- GUT unit tests: **6/6 PASS**, two suites (3+3) in logs; no pending/failing tests used to reach pass.
- Clean original world: **420 / 420 ticks PASS**, no phase abort, sampled N39 schema and world/ledger account reconciliation.
- New N9 receipts: **2168**
- Market physical stock changes between sampled checkpoints: **18**
- New facilities: **+1**
- New population groups: **+1**
- Research payment receipts: **+468**
- Flights observed by sampled `ship.transit`: **false**
- Completed N104 payout observed: **false**
- Approx. test-run throughput: **4.06 ticks/s on Linux hosted runner**, including source GDScript full simulation and periodic deep validation/snapshots; *NOT* Windows FPS or raw per-tick benchmark.

**Interpretation:** This conclusively shows the toolchain works and the original economy progresses without a human or injected need. It does **not** show end-to-end autonomous freight or full colonization/research technology completion. For strict physical paid freight call the existing `p2_autonomous_multitick_delivery_restart_check.gd` via the optional explicit workflow input or locally. A nonzero colony/technology/contract event in 420 ticks must be attributed to actual N39 source receipts, not an assumed UI state.

## Boundaries and coordination

An independent **active** stage2 lease `20261115-stage2-clean-seed-runtime-acceptance.json` owns `godot/scripts/sim/save_state.gd`, the existing P2 smoke workflow and `p2_stage2_clean_seed_420_tick_acceptance.gd`. **NONE of these files was modified** in this block. Our new CI trigger and GUT test runner are separate, and the official GUT plugin is not in the runtime dependency graph until explicitly installed.

**Next tests, not part of this block:** run true untouched free-running autonomous freight across many more ticks (if there is an actual shortage), separately run the controlled real paid N104→N153→N14→N21→N15→N9 delivery/restart, confirm head/admin self-directed construction/colony and finish with longer performance profiling (1000, 10000, 30000 ticks). The 4 TPS observed is a CI test metric; profile before changing engine or economy.

## Verification statement

**GUT_SETUP_PASS / GUT_6_OF_6_PASS / CLEAN_N158_420_PASS**, with exact CI logs and JSON artifact. **AUTONOMOUS_FREIGHT_NOT_YET_PROVEN / 10K_SOAK_NOT_RUN / WINDOWS_GUI_NOT_RUN**. No invented evidence or claims about player mandates.
