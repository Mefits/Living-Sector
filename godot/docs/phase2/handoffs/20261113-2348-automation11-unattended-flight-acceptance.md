# P2 unattended autonomous delivery — acceptance gate (13.11.2026 23:48 MSK)

- Shared PR #249, branch `integration/godot-phase2-unified-20261113`.
- Commits: `a6c9e0e0`, `6b279c80`; lease `20261113-2330-automation11-unattended-flight-acceptance.json` RELEASED.
- New code: `godot/tests/p2_unattended_autonomous_flight_check.gd`. A **real full-tick acceptance harness**, not a new simulation runtime.
- Reuses original frozen N4 seed, 24 ships, market ownership, route graph, N9 wallets, single N39 World and TickRunner. Fixture changes only alpha/earth food price and alpha consumption window; N135 computes a genuine proposal and existing N39 N104 posts funded order.
- Then up to 12,000 real single-runner ticks **without manual ship commands**. Requires N153 accepted obligation, N97/N15 physical pickup, observed N14 transit, N21 destination docking, N104 paid settlement and durable N9/N15 receipts. Checks global credit conservation on each tick.
- Saves to actual N38 disk **during a nonempty in-flight N14 transit**, boots a fresh runtime, reloads exact checkpoint, continues same voyage, and checks N104 escrow zero and replay refusal after payout.
- Does NOT teleport a ship, synthesize a cargo receipt, grant money or fake an arrival. If native autonomy is broken it must FAIL with a stage-specific error; it is not a claimed PASS.
- Validation: GitHub fetch of current source and static interface comparison with existing `p2_n153_live_contract_dispatch_check.gd`, `p2_live_funded_contract_check.gd`, `p2_native_paid_autonomous_delivery_check.gd`. No Godot 4.7.2 binary in this environment, so **CODE_UNVERIFIED**. No Actions run, no Windows ZIP.
- Potential issue: 12,000 ticks is an upper bound, not a promise of quick execution; run this only as a dedicated local integration checkpoint, not on every push.
- Local command: `godot --headless --path godot --script res://tests/p2_unattended_autonomous_flight_check.gd`.
- Next: run once in local Godot; fix the first actual parser/runtime failure in a coherent group, especially N14 arrival/BT progression or N97 escrow. Then verify full autonomous delivery on F5 without manual UI.
- Free files: test path and lease; no central runner, World, Ledger, ContractBoard, GUI or workflows modified.
