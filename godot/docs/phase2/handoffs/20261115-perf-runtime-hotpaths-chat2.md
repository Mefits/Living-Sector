# Living Sector — Chat №2 · Runtime hot paths S1–S8
Date: 2026-11-15. Branch: `feature/perf-runtime-hotpaths-20261115`. Draft PR: https://github.com/Mefits/Living-Sector/pull/260.

## Baseline / ownership
- Base `integration/godot-phase2-unified-20261113` exact SHA **`5f280ca617c874333dfd48410d6455e005a11361`**; PR [#257](https://github.com/Mefits/Living-Sector/pull/257) and [#258](https://github.com/Mefits/Living-Sector/pull/258) are already merged in this base.
- Only N158, N39, N39 tick runner and own new `p2_perf_runtime_*` tests/handoff. Chat №1 UI/main files, N9, N153, route_graph, CI workflow and N38 format not touched.
- **NO GITHUB ACTIONS LAUNCHED.** No local `godot` / `godot4` executable and no network-resolvable GitHub git clone in this environment. The new changes are **NOT COMPILED OR RUNTIME-VERIFIED HERE**; previous CI results are historical baseline evidence, NOT verification of this PR.

## S1 — Profile original N158/N39 (partial, measurement tooling added)
A real Godot 4.7.2 original-seed run from PR #257 (https://github.com/Mefits/Living-Sector/actions/runs/43733851184) recorded the following **900-tick** callsite values:
| Operation | Measured calls | Total | p95 |
| --- | ---: | ---: | ---: |
| N39 `copy:deep:L129` / public `world_snapshot` | 6243 | **33.670557 s** | **14.484 ms** |
| N39 `Schema.accounts`, all instrumented sites | 4715 | 0.508850 s | not consolidated |
| N39 `validate:L475` ship phase (earlier profile) | 787 | 4.440 s | 6.280 ms |
| N39 `copy:deep:L2008` (earlier profile) | 540 | 4.051 s | 10.536 ms |
| N39 `copy:deep:L196` lifecycle (earlier profile) | 540 | 3.690 s | 10.189 ms |

The latter three came from an earlier 900-tick profile under the same project but **not the same final run**; totals are not additive across runs. N39 has existing source-site sampled timings of `Schema.validate`, `Schema.accounts`, and deep/shallow World copies. N39 runner had total time/calls by native phase but lacked p95; this branch adds per-phase mean, p95, max, and opt-in N158 ship-stage distribution with negligible cost when disabled.

**New profiler** `godot/tests/p2_perf_runtime_hotpaths_profile.gd` uses the **original unmodified Rust 0.6.7 seed** and x8 native clock. Supports 420, 1,000, 10,000 actual ticks, exact N38 disk save+reload at 360 and own SHA256 checkpoints. Produces JSON with world cardinalities (ships/facilities/markets/populations/construction/contracts/N9 receipts), tick mean/p95/max, phases and per-N39 site call timings. These new runs are prepared but **NOT performed**.

## S2 — Residual hot-path ranking and mechanism (source audit + historical measurements)
1. Public N39 `world_snapshot()` deep-copy is the highest confirmed individual expense: 6,243 copies in 900 ticks (≈6.94 per tick), 33.67 s cumulative on the measured runner. It duplicates expanding N39 receipt registries, contract history and detailed ship/facility trees even for simple scalar membership checks.
2. Ship-associated full `Schema.validate` sites are next, with several hundreds of calls, each milliseconds (e.g. 4.44 s at L475 in earlier profile); **not disabled** by this branch.
3. Internal N39 deep staging `_copy_world` sites in lifecycle and ship phases have multi-second cumulative cost; their whole-world failure atomicity requires separate proven write-set equivalence before rewriting.
4. `Schema.accounts` cost is smaller in the cited original run (0.509 s / 4,715 calls); PR257 added safe N150/N21 validators, but no repeated clean validator has been bypassed here.
5. N84/N140/N153 ship-stage ranking and total N158 phases are *not independently established* in the available merged baseline. The local profiler captures N14, N83, N103, N80, N84 and N146 stage samples, plus whole native phases. Do not infer the bottleneck from selector-only N153 benchmark.

No inference of sustained Windows FPS or high-tick scaling is made from source static counts. Later 10k measurements must distinguish more N39 histories and receipts from real ship growth.

## S3 — Owned read/write domains: implemented; acceptance PENDING
Commit [242fffb](https://github.com/Mefits/Living-Sector/commit/242fffb8c40d71da27483e4e81ec7e0a5f93adb1):
- `native_ship_identity_snapshot()` returns a **fresh map containing only ID and faction scalars**; N148 no longer deep-copies all N39/N9-linked World registries to get one fleet membership roster every ship tick.
- `native_has_ship(ship_id)` tests canonical removal after N148 in N39, without a full World copy.
- `native_contract_kind(cid)` returns only original N104 type and mission category after every native N146 transaction attempt; no guessed contract types.
- `native_has_ship_domain()` replaces deep-copy of World just to determine enabled N158 phases; manual dock row uses existing `ships_snapshot()` rather than the whole World.
- All returned nested dictionaries are freshly allocated scalar DTOs, never references to mutable `_world`; no persistent cache/version and no N38 changes.
- Test `p2_perf_runtime_projection_parity.gd` checks exact IDs/factions/contract kinds vs true World and attempts to mutate the projection without changing the authoritative state. **Not executed here.**

## S4 — Validators: reviewed / no semantic change
Merged PR257 added local N150 observation / N21 dock validators with original Schema oracle after successful writes. On S1/S2 evidence, deleting or caching full `Schema.validate` would not preserve failure precedence without separate source-targeted negative tests. This iteration **does not remove or weaken any Schema/N9 validation**, rejection text, escrow, physical inventory, fuel, commands, RNG or N38.

## S5 — One-tick ephemeral read frame: implemented; acceptance PENDING
- N158 already creates one deep read frame `canonical` for N153. N104 passenger and N144 metals proposal stages now reuse it **only if no N39 acceptance was attempted** since the last snapshot.
- Every delivery or passenger admission attempt invalidates the read frame **before** invoking the N39 writer. On any potential write (including a nonfatal failure), the next proposal obtains a new N39 snapshot; no stale authoritative market, ship, wallet or contract state.
- Audited pure `N153Dispatch.propose`, `NativePassengers.propose_assignment` and `NativeColonyMetalAssignment.propose` stages. No frame may escape the stack or persist between ticks.
- `LS_PERF_NO_FACTION_FRAME_REUSE=1` **disables ONLY this sharing** for local same-build A/B; full source-code baseline requires actual base branch checkout. Runtime default is enabled. No change to frequencies, command order, contracts or RNG.
- Test `p2_perf_runtime_frame_parity.gd` compares SHA256 canonical checkpoint summaries for both variants at ticks 1/60/120/240/360/361/420 with actual N38 disk restart360. **Not executed here.**

## S6 — Ship stages: instrumented, not optimized by conjecture
- N158 opt-in `profile_native_ship_subphases()` returns counts, mean, p95, max and total for N14 physical motion, N83 trade, N103 mining, N80 exploration, N84 BT, N146 apply.
- `LS_PROFILE_SHIP_TRACE=1` enables old verbose per-tick print trace only if specifically requested, preventing massive profile logging overhead on 10k ticks.
- No change to SEARCH_BUDGET, N140 fired gate, N84 BT, real roster size, movement or stage cadence.

## S7 — Windows local tests and long profile: prepared, NOT RUN
From repository root, using your local Godot **4.7.2 console executable**:

```powershell
$godot = "C:\\Path\\To\\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path godot --script res://tests/p2_perf_runtime_projection_parity.gd
& $godot --headless --path godot --script res://tests/p2_perf_runtime_frame_parity.gd
& $godot --headless --path godot --script res://tests/p2_perf_runtime_hotpaths_profile.gd -- --ticks=420 --frame=original
& $godot --headless --path godot --script res://tests/p2_perf_runtime_hotpaths_profile.gd -- --ticks=420 --frame=optimized
& $godot --headless --path godot --script res://tests/p2_perf_runtime_hotpaths_profile.gd -- --ticks=1000 --frame=optimized
& $godot --headless --path godot --script res://tests/p2_perf_runtime_hotpaths_profile.gd -- --ticks=10000 --frame=optimized
```

Report files: Godot `user://tests/perf-runtime-<label>-<ticks>.json`, with N38 disk save at tick360 in `user://tests/perf-runtime-n38-<label>.json`. Save/reload outside per-tick stopwatch; counts per tick and stage timings are included. The 10k profile is **not yet proven feasible**.

## S8 — Same-machine comparison: PENDING
- `p2_perf_runtime_frame_parity.gd` performs exact source-runner N38 checkpoint parity with frame reuse enabled vs disabled (same code). A/B stopwatch in profiles can compare their costs on one Windows PC.
- No measured speedup or FPS claim yet. If full 420/N38/1000 tests uncover regression, disable frame reuse via `LS_PERF_NO_FACTION_FRAME_REUSE=1`, revise or revert it. Owned scalar projections remain separately reviewed.
- A full original-commit vs new-branch comparison still requires Windows checkout of base `5f280ca...` and the same exact profiler workflow. Do not claim correctness or gain until actual runs.

**Status:** S1/S2 source/historical-audit done and profiling infrastructure written; S3/S5/S6/S7 code prepared but parser/runtime unverified locally; S4 unchanged with full Schema proof; S8 awaiting real measurements. PR is Draft, no merge.
