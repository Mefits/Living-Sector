# Astra performance reconstruction — 2026-11-15 (experimental, not verified)

Base: `integration/godot-phase2-unified-20261113` at `4c315dc9`.
Branch: `feature/perf-astra-reconstruction-20261115`.

## Why
Astra reported a local N39/worker prototype but did not publish its source.
This branch is an **independent reconstruction** of those ideas, not recovered
Astra code. Do not claim her 188→145 ms improvement until Windows A/B confirms
it on this precise source. No GitHub Actions were started.

Baseline supplied by user (`perf-runtime-frame_optimized-420.json`, Godot 4.7.2):

- 420 original N158/N39 ticks in 124.55 s with profiler enabled; p95 561.63 ms
- phases: ships 57.52 s, factions 31.27 s, markets 25.59 s
- 3,497 detached full World snapshots / 11.88 s
- 3,769 Schema.validate / 26.56 s
- cost increased from ~258 ms/tick (1–360) to ~527 ms/tick (361–420)
- N38 save/restart360 passed; 24 ships, N9 receipts 3→2,189
- UI screenshots: ×8 tick87 FPS23, tick165 FPS6; ×16 tick277 FPS3,
  UI cost 2–3 ms, synchronous `advance_frame` ≫ UI

## Implemented in this branch

### N39 incremental owned staging (enabled; revert with environment variable)

- `run_tick` N156/N130 operating stage deep-copies **facilities, markets,
  populations**, not the immutable entire World/ship/contract histories.
  Verified source-stage mutators `Payroll.pay_shift` and `ServiceRestock.apply`
  write only these domains; rejected stages cannot mutate the canonical owner.
- N91 empty assignment fast path leaves the World/N9 unchanged without staging
  or redundant whole-World validation. Nonempty case retains original deep
  path and exact checks.
- N143 research skips staging only when **both** source shifts and head-state
  differences are absent. If a head changes or money is involved it retains
  complete N9/schema validation, with owned copies of its write domains.
- Replace 12 balance-only `Ledger.snapshot()[balances]` sites with
  `balances_snapshot()`. Full snapshots remain where historical receipt
  inspection, comparisons, untrusted proposals or N38 require them.
- Environment A/B toggle: `LS_PERF_N39_FORCE_LEGACY_STAGES=1` restores the
  old full World stages and empty-phase behavior. Toggle applies to new N39
  instances and never enters the game state/save.

### Experimental N158 worker owner (NOT connected to main.gd)

- New `n158_threaded_runner_owner.gd` creates and owns the **only**
  N158/N39 Runner on a Godot Thread.
- Main/UI thread can send detached FIFO control, advance, step batch,
  checkpoint, save/load requests; receives detached completed-result messages.
- Uses Mutex + Semaphore; never shares a live Runner, World, Ledger, BT or
  SceneTree object across threads. No second authoritative simulation.
- Includes 16- and 420-tick tests, original N38 disk checkpoint at tick360,
  canonical SHA256 checkpoints and an actual SceneTree callback counter
  while worker computes.
- This is **not yet a GUI FPS fix**: main.gd still runs synchronous simulation
  until a full GUI FrameView adapter and user Windows tests land.

## Tests to run locally on Windows (from Living-Sector\\godot)

Godot console path reported by user:
`D:\\PROGRAMS\\Godot_v4.7.2-stable_win64.exe\\Godot_v4.7.2-stable_win64_console.exe`

Run these first from PowerShell with `$godot` set to that path:

```powershell
$godot = "D:\\PROGRAMS\\Godot_v4.7.2-stable_win64.exe\\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path . --script res://tests/p2_perf_astra_worker_owner_parity.gd -- --ticks=16
& $godot --headless --path . --script res://tests/p2_perf_astra_n39_stage_parity.gd
& $godot --headless --path . --script res://tests/p2_perf_astra_worker_owner_parity.gd -- --ticks=420
```

Expected success markers respectively:

- `P2_PERF_ASTRA_WORKER_OWNER_PARITY_PASS ticks=16`
- `P2_PERF_ASTRA_N39_STAGE_PARITY_PASS`
- `P2_PERF_ASTRA_WORKER_OWNER_PARITY_PASS ticks=420`

Do NOT run the two long tests in parallel. The 420 parity run includes
**two real simulations** (legacy/optimized or synchronous/worker) plus N38.

For timing A/B against the user's own baseline, **profile each new arm** on
the same Windows machine with identical seed, speed, no concurrent tests,
clock and profiler flags. The run from Nov 15 includes profiler overhead and
must not be interpreted as FPS. Re-run the GUI FPS after the worker is wired
into the actual presentation, not after this isolated worker harness.

## Acceptance / future work
1. Fix any parser/runtime errors in the **new branch**, don't merge unverified.
2. Verify exact checkpoint equality of N39 legacy vs candidate on ticks
   1/60/120/240/360/361/420 and N38 restart360.
3. Verify identical states for single-owner worker vs synchronous 420 N158
   ticks (same physics, money, contracts, RNG, BT, and saved clock).
4. Measure actual CPU/tick; if there is no benefit from owned stages, revert.
5. Only then connect **immutable detached committed FrameView** to Observer,
   fleet and orbit map, and route all UI commands/save/load through worker
   queue. No simultaneous live _runner access on UI thread, no mutable
   cross-thread `world` references, no lock held over expensive ticks.
6. Windows FPS acceptance with pause/×1/×8/×16, sector/system view,
   after 420 and 900 ticks. Do not claim FPS improvement before this.

Guardrails: no balance changes, no synthetic ships/receipts, no removed
atomicity checks, no shortcuts in N9 or N38, no unvalidated receipt journal
mutation, no automatic merge, and no GitHub Actions on user's budget.
