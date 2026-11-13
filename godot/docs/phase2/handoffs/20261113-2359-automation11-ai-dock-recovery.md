# P2 / N84 physical warehouse docking recovery — 13.11.2026 23:59 MSK

- Worker: automation11-recovery; integration branch / PR #249.
- Code commit: `c9ee6f4a95fbbcf3e26d455a3901323287f84993`.
- Changed only `godot/scripts/sim/phase2/unified_ship_ai_execution.gd`.
- Dock leaf now issues N146 ReleaseDock when ship occupies another physical N21 facility; retries contract's exact market owner next tick instead of failing whole N158 phase.
- Buy and DeliverCargo leaves now require `docked_at == markets[location].owner`; on missing/wrong dock issue N146 RequestDock/ReleaseDock respectively before N97/N104 physical cargo Apply.
- No synthetic receipts, no new ledger/world/runner, no manual controls.
- Static verification: read exact code before edit; three scoped substitutions and SHA-checked GitHub update succeeded. Godot 4.7.2 unavailable: **WIRED_CODE_UNVERIFIED**. Actions: **0**.
- Important concurrent lease: `20261113-2356-automation11-contract-dock-target.json` owns N21 registry/fleet logistics; not touched.
- Remaining: run local Godot parser + multi-tick hands-off acceptance, verify wrong-dock recovery and save/load, including no double payment.
- Lease `20261113-2358-automation11-ai-dock-recovery.json`: RELEASED.
