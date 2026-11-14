# 14 Nov 2026 — N152/N145 expiration, renewal and real N104/N9 escrow refunds

Branch: `integration/godot-phase2-unified-20261113` (single working PR #249).
User instruction: finish ALL frozen Rust-to-Godot source integration before gameplay tests, balance changes and further Actions runs.

## Verified source facts / dependencies
- Frozen Rust `native/crates/sim_core/src/economy/contracts.rs`: `ContractBoard::age_open_reputation`, `age_escalate_payment`, `sweep_expiring`, `expire_unclaimed`, `drop_ship_holdings`, `cancel_for_facility`. Source escrow `engine/contract_funding.rs::refund_closed` returns unused reserves on Paid/Expired.
- N152 P1 structural port PR #241 already SOURCE-COVERED, but was not executable in the canonical P2 N39 World. We did NOT duplicate its board or start a second tick runner.
- N145 source port `native_contract_aging.gd`: original Posted-only rep/payment aging; delivery and construction can renew 3x, subsidy 1x, others do not renew. The existing source default lifespan is 300 ticks. `accepted`/`picked_up` are never automatically expired, since real freight obligations persist.
- Existing N104 canonical `contract_board.gd` owns physical N15 receipt validation and status transitions, `credit_ledger.gd` owns N9 financial transfer IDs, N38 checkpoint retains the only snapshots, N121 awaits a genuine N9 refund receipt.

## Work committed to the shared branch
1. New `godot/scripts/sim/phase2/unified_n152_contract_lifecycle.gd`: stages the CURRENT N104 board and N9 ledger on private snapshots. Applies original N145 aging/renewal policy, closes truly expired unaccepted offers, and invokes the same N104 `refund_closed` for Paid/Expired unused reserves. Every refund has one `contract:<id>:refund` N9 receipt. No physical goods, ships, wages, or money are invented.
2. `n39_native_world_production.gd::apply_native_n152_contract_lifecycle`: one authoritative atomic Apply after prior physical production tick; validates exact contract identity/history, permitted N145 offer-field changes, real escrow-to-original-payer legs, ledger total, receipt provenance, and ALL Schema.accounts balances before swapping World and Ledger together.
3. `n158_production_runtime.gd`: calls N152 from the real market phase after N150 market update and BEFORE fresh N135 post-funded demand, so expired unaccepted orders cannot continue monopolizing demand or trap payer funds. Exposes expiry, renewal, refund and blocked-refund counts in the existing observer result. N152 errors halt the single integrated clock rather than silently skipping broken settlements.
4. Existing canonical `contract_board.gd::post` now persists original `renewal_count`, `min_reputation`, `initial_min_reputation` with source type gates (public delivery 0; subsidy 70; crew mission 50); previously saved contracts use the source N145 defaults without creating new cash.
5. `native_contract_aging.gd` accepts canonical P2 `funding_source=faction` when the original nested Rust funding descriptor is absent; N121 `strategy.logistics.v1` retains its source FIXED reward through aging/renewal and must not be silently escalated.
6. N38 restore normalizes optional newly persisted N145 fields; older saves lacking them are not backfilled and are not rejected simply for their absence.

## Non-destructive, receipt-backed semantics
- POSTED age/renewal only; no time-expiry of ACCEPTED or PICKED_UP.
- PAID/EXPIRED leftover escrow returns to its ACTUAL posting facility, population or faction N9 wallet; no treasury fallback for a missing payee.
- Missing or overflowing beneficiary: the closed contract and original escrow balance persist for later recovery, not a fabricated successful refund.
- Real receipts are append-only, with idempotent `contract:<id>:refund`; already-zero reserve does not transfer twice.
- Paid/Expired contract rows and N15 receipts remain archived as durable history because N98/N121 need to reconcile actual order outcome after restart; no historical deletion.
- All updates are staged as one native N39 commit. Any mismatch rejects the entire proposal, not a partial money mutation.

## Verification status / remaining source work
- Static GitHub readback on all 5 affected GDScript files: delimiters/quotes, NUL, UTF-8 newline and edited import/reference existence checked. No Godot parser, headless or GUI runtime, no actual Rust/Godot differential test; **CODE_UNVERIFIED, SOURCE_WIRED**, no new GitHub Actions.
- The N145 `DEFAULT_EXPIRE_LIFESPAN = 300` is the frozen source shim; an original engine call-site with a custom lifespan may need final parity reconciliation. This block does not claim such a runtime parity result.
- Ship-deletion `drop_ship_holdings` and facility-deletion `cancel_for_facility` admin paths of P1 N152 are NOT additionally connected here; do not claim the whole admin-cleanup domain completed. These need subsequent real admin deletion entrypoints and safe escrow cleanup without duplicating payments.
- End-to-end pick-up/paid delivery/expiry, N121 terminal failure, save/restart and all Godot parser checks remain deferred until ALL source integration is complete, per user instruction. Never label this USER_WINDOWS_PASS or VERIFIED.

## Later acceptance scenarios (documented, NOT run)
1. POSTED delivery at first expiry renews, after 3 renewals expires; no second contract ID or escrow debit.
2. N121 faction project reward remains fixed even when the offer ages; expired order refunds ORIGINAL faction wallet and only then N98 can observe terminal failure.
3. Missing payer leaves escrow untouched and reports blocked; restoring a valid wallet permits exactly one real refund receipt.
4. PAID with overfunded escrow receives only the residual amount; N9 total remains invariant.
5. ACCEPTED/PICKED_UP freight never disappears at its offer expiry.
6. Save/load preserves renewal count, posted price, closed history, receipt claim provenance and refunds exactly once.
