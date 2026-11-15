# CHAT №3 — В3 / N38 lossy JSON guard for the single economic frame

Date: 14.11.2026 · PR #249 · `integration/godot-phase2-unified-20261113`

## Source and concrete defect

`godot/scripts/sim/save_state.gd` previously performed an N38 SHA256-envelope roundtrip and checked only the N39 **market supply** against the live in-memory checkpoint. That does not prove an exact JSON roundtrip for N9 wallets, i64 receipt legs, N104 contracts, ship cargo, faction research, director state, strategic plans or persisted event flags. Both hash producer and validator could accept an already-lossy JSON serialization; original Rust money is i64.

Frozen canonical shape: `n39_native_world_production.gd::snapshot` returns one `{"version","tick","world","ledger"}`, with N9 `balances` and immutable `receipts` and N104 board inside World. This block changes **only** pre-promotion verification, not original mechanics or the ledger implementation.

## Implemented on the shared branch

- `c12b5de` — new `godot/scripts/sim/phase2/unified_native_save_roundtrip_guard.gd`: recursively compares *every* original value in native World and N9 ledger against JSON-decoded checkpoint before accepting a save. Field identity and array cardinality preserved. Preserves exact ints even if JSON parser materializes as float; disallows lossy i64→float (outside ±(2^53−1)); checks all floats are finite/unchanged, flags, strings, contract status, cargo, receipt leg deltas and planner records. Rejects JSON-inexpressible map keys and type-changing objects. Legacy P1 without N39 remains accepted.
- `75b14e4` — existing `save_state.gd::save_runner`: after writing `.pending` and verifying envelope SHA, additionally checks `NativeFrameGuard.verify_authoritative_frame(snapshot, verified)` alongside existing stock verification **before** replacing original or backup. On failure it removes pending and returns `ERR_FILE_CORRUPT`. P1 format, save paths, fallback precedence and N38 digest unaffected.
- `86762fd`, `e4ba07d` — `godot/tests/p2_native_save_roundtrip_guard_check.gd`: JSON envelope/Guard comparison, mutation of N9 wallets, contract escrow legs, ship hold, contract status, N121 plan, crisis flags, facility fields, unsafe i64; checks a temporary real N38 `save_runner` file and ensures invalid promotion does not damage healthy primary or create an unsafe backup. **Test authored, NOT RUN.**

## Coordination & status

**N38_GUARD_SOURCE_WIRED / CODE_UNVERIFIED**. All three changed files fetched again; balanced brackets/parentheses, final newlines, no NUL. Godot parser/headless/runtime not run, Actions=0 as required.

No edits to N39/N158/Schema/N9 ledger/Board or Chat2 colony scripts. Chat1 trade and Chat2 B2 Metals active reservations remain untouched. Prior V2 market/facility warnings also remain partial: N158 event-dispatch and facility `starving_notified` atomic Apply depend on their central shared-file release.

## Next on «Продолжай»

1. Re-read PR #249 HEAD and active leases. If chat1 and chat2 finished central writes, finish V2 Rust `markets→crisis→apply2→factions` with N39-staged facility `starving_notified`, original transition events emitted only once by existing N158 EventQueue/signal and N38 persistence.
2. Otherwise continue V3 cross-snapshot architecture/source parity in files outside reserved paths: check phase event ordering, save migration and orphaned durable receipts; no artificial wallet, clock or contract authority.
3. At **final** combined Godot/Windows acceptance, execute `p2_native_save_roundtrip_guard_check.gd` and pre-existing N158 save/load regression. Check performance for large N9 receipt archives; no intermediate Actions.

Do not claim runtime PASS, full V2 or full V3 completion until actual Godot results.
