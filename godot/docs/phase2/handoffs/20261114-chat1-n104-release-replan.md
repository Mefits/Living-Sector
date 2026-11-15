# Living Sector P2 — Chat №1: N104 timeout failure, guarded ReleaseContract, physical resume

**Date:** 2026-11-14  
**Branch:** `integration/godot-phase2-unified-20261113` · shared draft [PR #249](https://github.com/Mefits/Living-Sector/pull/249).  
**Status:** **SOURCE_WIRED / CODE_UNVERIFIED / RUNTIME_UNVERIFIED**. Source changes are pushed; Godot parser, headless, F5, long-game/Windows runs and deferred scenario fixtures have **NOT** been executed.

## Source facts, not assumptions

- Frozen Rust `native/crates/sim_core/src/agents/ship/actions.rs`: `ShipAction::Dock` returns `Failure` after N21 original **150 (contract) / 60 (ordinary) / 30 (low morale)** base ticks × tick multiplier; its saved `ShipEconomy.dock_attempt_start_tick` is cleared.
- Frozen Rust `agents/ship/behavior.rs`: on failing BT, ship drops the BT and emits `SimCommand::ReleaseContract`; after a successful release the planner may select another real N104 offer/hull. `resume_contract_bt` builds an N81 GOAP BT from current location, status, real cargo and fuel on a held `Accepted/PickedUp` contract, without reaccepting it.
- Frozen Rust `native/crates/sim_server/src/engine/apply.rs`: release is **guarded by the matching fulfiller** and applies one breach penalty `clamp(10 + payment/1000, 1, 25)` (except issuer funding failure). Faction standing penalty is -1 if factions differ. No source money refund.
- Frozen `contracts.rs::ContractBoard::release`: only `Accepted → Posted`. `PickedUp` is a no-op, not a second source delivery, and fixed faction strategy offer payment goes back to its initial authorized amount.

## Actual source implementation

1. **NEW** `godot/scripts/sim/phase2/unified_n104_release_stage.gd`: staged pure N104 release of `Accepted` with real matched fulfiller only; clears assignment and marks `Posted`, clears accepted/agreed cursors, preserves **escrow/reserved/N9 balances/receipt claims/physical cargo**. Original ship reputation and N150 source relations receive one breach penalty. Existing original faction-fixed logistics/construction/colony strategy reward restores `initial_payment`.
2. `godot/scripts/sim/phase2/unified_ship_ai_execution.gd`: on real failed N84 BT, `Accepted` without physical paid cargo emits **one N146 `ReleaseContract`** instead of freezing or endlessly retrying N21. N84 leaves the real ship's `active_contract_id` intact until N39 Apply verifies the matching Board owner. Original N90 pending mailbox is cancelled through the existing source slot, not by inventing a market trade. The next native N153 decision may re-bid the existing posted offer.
3. `godot/scripts/sim/phase1/n39_native_world_production.gd::apply_native_n104_release_contract`: only canonical atomic Apply **after N84 ship phase**, with `planning_source` authenticated as N84 failure. Checks World domain allowlist, unchanged other physical ships and N104 contracts, immutable original N104 receipt claims, full N39 schema and **exact N9 account equality** before publishing board+ship+relations. No second contract board or ledger.
4. `godot/scripts/sim/phase2/n158_production_runtime.gd`: consumes the **one real N146** release command `ship/ship_id/contract_id/reason` through N39, records successful release in existing ships result. Losing/duplicate speculative claim cannot unseat the named fulfiller.
5. **NEW** `godot/scripts/sim/phase2/unified_n104_contract_resume.gd`: frozen Rust `resume_contract_bt` concept port using **existing `N81 Goap.plan` + `N153 Plans.resume_contract_request / compile_plan_to_bt_actions`** and real directed N4 graph **plus reciprocal physically built N108 GateLinks**. On a physically `PickedUp` job, no `AcceptContract`, `Buy` or `EmbarkPassengers` may be repeated, no invented shipment. Builds a serializable original `Dock → DeliverCargo` continuation (plus real Travel, dwell or refuel leaves when selected) from current position/hold. Also recovers real held contracts whose N38 checkpoint contains a missing BT.
6. The previous `PickedUp` safe-retry fallback is replaced by real resumed N81 planning when a route exists. If real cargo or route proof is absent, retain N104 assignment and escrow and report a blocked replan; fail closed rather than grant an already-loaded second pickup.
7. `godot/tools/p2_v4_source_gate.py` now checks these specific N84/N146/N39, N104 release and cargo-resume links in the existing single source audit.

### Explicit safety divergence

The literal Rust BT-failure path removes the active ship contract even when the Board is already `PickedUp`, while `ContractBoard::release` refuses that state. That can strand an original paid cargo obligation. The Godot bridge instead **retains `PickedUp` and uses Rust's own `resume_contract_bt` logic** immediately. This protects physical goods and escrow; it is not a claim of identical tick-by-tick chronology. `Accepted` release matches the original authority and penalty behavior.

## Authored but NOT executed

`godot/tests/p2_n104_contract_replan_source_check.gd` covers:

- N84 emits one genuine N146 ReleaseContract after original N21 timeout for accepted cargo-free job
- Real N104 Board `Accepted → Posted`, same escrow and wallets, correct breach penalty
- Duplicate command or loser actor cannot revoke a different fulfiller
- `issuer_funding_failure` waives the penalty, original faction strategy rewards restore authorized price
- Physical `PickedUp` job creates no release, no extra `Buy`, no extra `Accept`, preserves loaded cargo and creates real N81 delivery BT
- N38 missing-BT checkpoint rebuild from the held cargo
- Missing physical cargo and unreachable directed route fail closed
- Loaded interstellar contract uses a real existing reciprocal N108 gate pair to construct a GateJump action; an unpaired/ghost gate is rejected. N108/N9 still settle the actual jump and its fee at Apply time.

**Static GitHub readback:** seven touched source/test/audit files including the later authentic N108 gate route fallback, terminated source strings and brackets, UTF-8 LF/EOF, no NUL, required cross-file callsites: **7/7 pass**. No Godot parser or runtime PASS. The fixture is intentionally deferred until the coordinated one-project acceptance.

## Current frontier

This closes the previously named **N104 Dock-timeout replan source-link gap**. Source integration still must pass the existing combined `p2_v4_source_gate.py --require-complete --json` and the **A/B/V/G one-project Godot/Windows acceptance**. A real `N104 Accepted → N146 Release → Posted → another N153 ship wins` scenario and a saved `PickedUp` freight delivery must run in Godot to prove actual behavior. No balance, new fleets, phantom resources, market offers, extra schedulers or GitHub Actions were introduced.

**Lease:** `godot/docs/phase2/leases/20261114-chat1-n104-contract-timeout-replan.json` (released after writing this report).
