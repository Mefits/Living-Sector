# Living Sector P2 — Stage 1: critical integration and N38 repair

**Date:** 2026-11-14  
**PR:** [#249](https://github.com/Mefits/Living-Sector/pull/249)  
**Tested code commit:** `b40a9428b0314b5d63e51d1d8303d539f5009f62`  
**Verification:** **GODOT_4_7_2_INTEGRATED_SMOKE_PASS** (runtime, not merely static source checks)  
**Run:** [Godot P2 unified smoke #43642388330](https://github.com/Mefits/Living-Sector/actions/runs/43642388330)

## What was broken and what actually changed

1. **N91 ship construction executor:** `godot/scripts/ported/n91_construction_executor.gd` compared the Variant `action` (sometimes a Dictionary) directly with a String. On the real native ship phase this emitted `Invalid operands 'Dictionary' and 'String' in operator '=='`. Both legacy String checks are now guarded with `action is String`; the canonical Dictionary BT action remains the preferred path.
2. **N158 phase diagnostic:** `implemented_phases()` listed `crisis` twice. The legacy `p2_n158_live_production_check.gd` expected a phase list predating `dock_queue`, `crisis`, `relations`. The diagnostic now advertises each real phase once; the test asserts the current explicit list rather than rolling the simulation back.
3. **N38 JSON precision:** real N155 director personality, N156 facility condition, and paid N39 work-shift output doubles did not always round-trip bit-for-bit through Godot JSON. The former guard rejected legitimate saves (error 16). `unified_native_save_roundtrip_guard.gd` now permits only finite, relative `<= 1e-12` decimal quantization outside protected authoritative domains. It still denies loss in market physical supply, ship cargo, escrow, contract board, N9 ledger and exact 64-bit money. `SaveState._physical_stock_matches` remains strict; hash/backup and coherence/timeline checks remain unchanged.
4. **N101/N108 N38 ship restoration:** `n158_production_runtime.gd` converts exact integral saved `ShipProgression.level/xp/retrofit_points` back to TYPE_INT before N39 validation; `ship_state.gd` recomputes N108 fitting characteristics from *actual installed module slots* and compares derived floats with only `1e-12` absolute tolerance, while keeping integer power, Boolean flags and the real module catalogue strict.
5. **N150/N129/N18 N38 source cursors:** exact integral relations/territory/finance/administrator ticks and source treaty timestamps are normalized on a detached checkpoint before the existing strict N39 Schema check. No missing fields or fractional ticks are backfilled or rounded.
6. **Regression diagnostics:** Gate4 N143 test now rejects a material alteration to science personality and even one counterfeit faction credit; both Gate4 N143 and N158 paid-production smoke expose the responsible read-only guard and schema rejection on future failures. No new clock or second ledger was introduced.

## Evidence from actual Godot 4.7.2

The checked-out commit was run in GitHub Actions with the existing `.github/workflows/p2-unified-godot-smoke.yml`:

- `P2_CI_RESULT editor=0 parse=0 economy=0 research=0`
- `P2_UNIFIED_PARSE_SCAN: loaded=310 total=310 failures=0`
- `P2_UNIFIED_ECONOMY_ACCEPTANCE_PASS: source 8/3, N39 production, N151 paid Food/Water, N150 price/trend, single ledger, saved/restarted`
- `P2_GATE4_ORIGINAL_N143_PAID_RESEARCH_N9_SAVE_PASS`

The production scenario exercises original 8/3 seed, 24 canonical ships, native production and consumption, five ticks, an N38 disk checkpoint, a fresh runner reload, 10- and 16-tick continuation and market trend; the science scenario executes real paid research N9 receipts, N38 save/reload, continuing paid shifts, technology completion and a strict no-replay check. These are **real headless Godot passes on this source commit**, not merely authored fixtures.

Earlier Stage 1 runs found successive invalid serialized native fields; the final smoke above supersedes their failures at its tested commit.

## Scope and limits

**Stage 1 finished.** N91, N158 phase registry, N38 save/load and N143 paid research now pass the actual combined smoke. No balance or gameplay mechanics have been changed.

**Not yet verified:** autonomy A (independent Head→N104→N14→N21→N15 paid delivery), full colony B, Head/admin V, full Windows G and long 1,000–30,000+ tick performance. This is **not** a claim of whole-game `SOURCE_INTEGRATION_COMPLETE`, complete Rust parity, or Windows playtest PASS.

Next separate macroblocks: full paid execution of player economic mandates N109/N110→N111→N121/N104/N9; then one whole-game A/B/V/G acceptance and performance profiling. Avoid intermediate micro-PRs or changes to balance during this phase.

**Lease:** `godot/docs/phase2/leases/20261114-chat1-stage1-integrated-runtime-repair.json` released after this handoff.
