# Living Sector — Stage 2: 420 actual Godot ticks and N38 restart through tick 361

**Date:** 2026-11-15 (Moscow)  
**Unified branch:** `integration/godot-phase2-unified-20261113`, Draft PR #249  
**Actually tested SHA:** `d3473f36f1976235ff32bc5e1bc7a6e84736bec2`  
**Real Godot 4.7.2 run:** https://github.com/Mefits/Living-Sector/actions/runs/43647029802  
**Outcome:** `GODOT_4_7_2_STAGE2_CLEAN_NATIVE_TICK420_N38_RESTART_PASS` — bounded clean-seed continuity only, NOT full autonomous A/Б/В/Г acceptance.

## Verified in the real Godot runner

The original frozen Galaxy seed was loaded *without* injected ships, demand, cargo, contracts, faction funds, markets or synthetic route edges: 8 systems, 3 factions, 24 ships, 15 paid facilities and 3 markets. The single N158/N39 TickRunner executed source phases and the canonical N9 ledger. The test stepped exactly 420 native ticks at world speed x8 and checked phase rejection, source actor/contract continuity, ledger balances versus immutable receipts and original money sink semantics (crew wages/decommissions).

At tick **360**, the test wrote the actual complete N38 disk checkpoint, booted a separate new N158 runner, loaded that file with the existing SaveState API, checked the entire canonical economic frame via `NativeFrameGuard.verify_authoritative_frame` (including N9 money/escrow/receipts, N104 contracts, N15 cargo and physical stocks) and proceeded through **361 to 420**. All checks passed.

| Actual marker | Result |
|---|---|
| `P2_UNIFIED_PARSE_SCAN: loaded=310 total=310 failures=0` | PASS |
| `P2_UNIFIED_ECONOMY_ACCEPTANCE_PASS` | PASS |
| `P2_GATE4_ORIGINAL_N143_PAID_RESEARCH_N9_SAVE_PASS` | PASS |
| `P2_N91_SOURCE_N151_MARKETLESS_RECEIPTED_DOCK_PASS` | PASS |
| `P2_N38_NATIVE_F64_EXACT_JSON_ENVELOPE_PASS` | PASS |
| `P2_STAGE2_CLEAN_NATIVE_TICK420_N38_RESTART_PASS` | PASS |

Source trace samples: tick 60 = 441 N9 receipts; tick 240 = 1445 N9 receipts and one real funded contract; tick 360 = 1925 receipts; tick 420 = 2168 receipts and the same 24 ships. Ship-crew wage sinks are legitimate original Rust one-leg N9 receipts; no unexplained money changes were accepted. A funded contract at tick 240 does **not** constitute end-to-end physical delivery.

## Source fixes for real defects

1. **N91/N151 colony dock:** original Rust `prepare_docks` creates a receipt-backed `construction_dock` before a station and Market exist. The N91 source selector and the N39 authoritative Apply no longer fatally require a conventional Market for this legitimate colony path; they require the exact physical N151 dock receipt, matching faction/site/location and live dock. An N91 engineer still cannot be assigned until the full original construction materials have been physically delivered with paid receipts. This fixed the source clean-world `factions tick=181 reason=n91_site_without_real_market` rejection found in actual CI.
2. **N38 exact serialization:** ordinary Godot JSON rounded some original IEEE-754 floating-point physical stock and N150 history values, so the strict source save guard correctly rejected late checkpoints. The existing SHA-protected N38 v1 JSON envelope now transports each float as eight exact IEEE-754 bytes; dictionaries with typed non-String keys (observed in N81 contract Behavior Trees) use an authenticated typed binary token rather than silently changing a `contract_id` key. Old untagged v1 and P1 checkpoints remain readable. No live world/ledger/AI/economy calculation was rounded or changed.
3. **Acceptance contract:** one clean-seed 420-tick test now checks ledger deltas against authoritative immutable receipts, not incorrect zero-sum accounting that would treat original crew wage accrual as money creation/loss. N38 post-load comparison uses the same strict native frame contract as production, not raw `Dictionary ==` which incorrectly rejects JSON `1` vs `1.0` before exact integral normalization.
4. **Bounded CI:** the shared smoke workflow now aborts immediately on parser or short codec/production failures, avoiding costly downstream Godot timeouts when a fundamental dependency did not compile. No new PR or duplicate TickRunner was created.

## Important limits and the next macroblock

This is **not `SOURCE_INTEGRATION_COMPLETE`** and does not prove full A/Б/В/Г. Still required: unattended Head/N135→N104→N153→N14→N21→N15→N9 *paid physical delivery*, original paid colony foundation including passengers/materials/labor, multi-strategy Director/mandate execution, Windows GUI build/playtest and a long soak. The user's previously observed Windows tick-361 rejection stopped reproducing after their own update; our independent headless pass through tick 361 now confirms that narrow boundary on the tested SHA only. No gameplay/balance revisions requested for later were applied.

**Performance flag:** the bounded test took 116,476 ms for 420 ticks in CI including N9 audit and one N38 disk restart. Duration rose as native receipts accumulated (60 ticks ~7.4s, 240 ticks ~47.5s cumulative, 360 ticks ~87.8s). This is not an isolated simulator benchmark, so it does NOT prove a specific subsystem is quadratic. The next performance macroblock should measure N39 `world_snapshot` deep-copy, full-world validation, per-tick N9 receipt scans and UI updates separately at 100/1,000/10,000 ticks. Do not optimize blindly or alter Rust semantics.

**Note on concurrent integration tooling:** commits following tested SHA were inspected; through `e556ccc` they affected GUT/test tooling/docs only, not the tested simulation source files. The statement of PASS applies exactly to tested SHA `d3473f36`.
