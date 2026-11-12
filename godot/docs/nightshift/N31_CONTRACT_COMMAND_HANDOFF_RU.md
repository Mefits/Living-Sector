# N31 — Tick-driven contract command dispatcher (CODE_UNVERIFIED)

## Source and scope
Rust frozen reference: `sim_core/economy/contracts.rs`, `sim_server/engine/contract_funding.rs`. Depends on N15/N16/N26/N27/N30. The new `contract_command_runner.gd` schedules real physical pickup, delivery and escrow payout commands at authoritative simulation ticks. It is **not** a replacement for the existing N3 event queue or a second game clock: the owning world must invoke `advance(tick)` once per committed tick.

## Invariants
- Command IDs are immutable and cannot be resubmitted after execution; duplicate or backwards ticks are rejected.
- Due commands execute in deterministic `(due_tick, command_id)` order independent of FPS or enqueue order.
- Every command requires a healthy pre-operation N30 cross-ledger audit; unsupported contract types fail closed.
- Pickup and delivery use N26 physical transfer and N27 verified cargo receipts, not fabricated quantities. Payout uses existing N11 ledger and N27 contract gate.
- Warehouses are **bound by reference** to authoritative stocks, never instantiated with fictitious stock.
- `snapshot/restore` preserves pending/executed IDs and tick monotonicity; it does not replay already committed operations. Restore only after authoritative cargo/board/ledger/ships/stocks restore.
- Post-operation audit failure is reported explicitly; it is NOT a rollback. No false claim of atomic cross-system rollback.

## Engineering decision
Godot built-in `RefCounted` + `Dictionary` avoids a SceneTree node per contract. The fixed-step command pattern follows Godot data separation and Game Programming Patterns (Command/Event Queue). A third-party behavior-tree or ECS addon would not provide transaction semantics; no plugin added. Runtime performance at thousands of contracts still needs measurement.

## Acceptance
```bash
godot --headless --path godot --script res://tests/n31_contract_command_runner_check.gd
```
Test checks ordering, duplicate suppression, real warehouse and wallet conservation, payout exactly once, restore without replay and fail-closed invalid restore. No Godot runtime test has run in the agent environment: **CODE_UNVERIFIED**.

## Remaining integration
Hook this dispatcher to the authoritative N3/N23 tick phase (without a duplicate clock); bind real warehouses from the world registry and ensure travel/docking preconditions from N29 are authoritative. Existing N15 direct `move()` remains a separate caller boundary. Need stronger transactional recovery for crashes between cargo transfer and contract state update, and recipient wallet provenance for payouts.
