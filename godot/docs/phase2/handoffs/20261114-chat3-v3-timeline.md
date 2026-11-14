# Living Sector P2 — чат №3 · В3 / единая временная шкала

Дата: 14.11.2026 | общий PR #249 | ветка `integration/godot-phase2-unified-20261113`.

## Найденный реальный разрыв

До этого в N38–N39 уже проверялись согласованность N9 и тик N39 с N1, а N158 при восстановлении JSON приводил `MarketHistory.last_tick`, `spawned_at_tick` и `trend_samples[].tick` к integer-типам. Но **не было проверки всех этих дат относительно единственного `checkpoint.tick`**; сама `n39_native_world_production.gd::restore` проверяла часть фракционных курсоров и payroll, но не будущие рыночные тренды или сохранённые реальные N15/N21/N108 квитанции. Корректная SHA256-оболочка может содержать такую логически несогласованную историю.

Frozen Rust reference: `native/crates/sim_core/src/agents/market.rs` / Godot source port `n150_native_full_market_tick.gd::tick_one_market`. Source writes `history.last_tick = tick`, `spawned_at_tick` only at first tick and retains max 200 ascending `trend_samples` (each 16 raw ticks). Existing N15/N21 and N108 receipts represent already-executed operations. Conversely, `ship.transit.arrival_tick`, N104 expiry, N140 next-tick and N1 event due are future deadlines, **not completed events** and must NOT be bounded by current tick.

## Committed implementation

- `7cc1dcc` — new pure `godot/scripts/sim/phase2/unified_native_timeline_integrity.gd`: verifies canonical N38/N39 tick identity; saved N150 market last_tick and spawned_at_tick not beyond committed tick; monotonic trend samples each <= market last_tick, max 200; consumption samples <= committed tick; already-executed physical `dock_receipts`, `cargo_receipts`, `native_gate_jump_receipts` <= committed tick; ship observed `departure_tick`, `last_tick` <= current tick while allowing actual future `arrival_tick` and future N1 notifications. Uses exact numeric check for JSON parser's float representation; does not modify data or infer calendar hours from `tick * speed`.
- `9e8f724` — integration in `godot/scripts/sim/save_state.gd` at **three N38 boundaries**: (1) pre-save source checkpoint before writing pending, (2) pre-rotation trust evaluation for existing primary, (3) every read candidate before `Runner.restore_checkpoint`. Allows fallback to `.bak` for a SHA-valid primary that would time-travel N150 market history. No duplicate TickRunner, Clock, Ledger, ContractBoard or World.
- `cdd1f15` — new deferred `godot/tests/p2_native_timeline_coherence_check.gd`, NOT RUN: valid tick 32 with trends 16/32, receipts 10/20/31, ship observed last 31 + future arrival 50 + future N1 due 36, rejects spawned/market/trend/consumption/physical receipt future timestamps and unsorted trend history, rejects ship departure/arrival incoherence. Checks JSON decode, N38 pre-save fail-closed file integrity, SHA-valid future-market primary fallback to healthy backup and legacy P1 no N39.

## What was NOT done

No edits to `n39_native_world_production.gd`, `n39_native_world_schema.gd`, `n158_production_runtime.gd`, `tick_runner.gd`, Clock, Calendar, Ledger, ContractBoard, N104, N150 economic phase or any gameplay balance. Concurrent Chat1 and Chat2 may still modify shared N39/N158. The timeline gate is a read-only N38 assertion.

**Status: SOURCE_WIRED / CODE_UNVERIFIED.** Static GitHub readback for three files: matching brackets/parentheses/braces, quote parity, no tabs/NUL, trailing newlines. Godot editor/parser/headless/Windows and GitHub Actions **NOT RUN** (no intermediate runs per user). Source tests authored, NOT executed. Do not label full Rust integration, round-trip, or acceptance PASS.

## Next on «Продолжай»

1. Recheck latest GitHub HEAD and active leases. When other chats release shared files, finish V2 source `markets→crisis→apply2` with exactly-once N39 facility starving flags and native event dispatch. No accidental duplicate clocks.
2. If the user again directs independent V3 work, inspect source-vs-save timeline for other historical *completed* receipts/cursors (excluding future ETA/due), or save recovery overhead while preserving old-version snapshots.
3. At final joint test run the new `p2_native_timeline_coherence_check.gd` alongside previous V3 N38/N39/N9, JSON fidelity and recovery tests; verify real source P2 world tick 16, market trend sample, consumption event time and backed-up restore. Log actual results.
