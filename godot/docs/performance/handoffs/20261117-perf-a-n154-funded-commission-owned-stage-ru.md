# PERF A · 17.11.2026 · N154 funded construction commission

Branch: `integration/perf-astra-5-workers-20261116`, PR #262.

- Code commit: `081b4765de1d0a07a18fad04e85e46f0d5bd4742`.
- Test commit: `e7e389e5e6b99450b8aaaf483734525817df2f01`.
- Changed: `godot/scripts/sim/phase1/n39_native_world_production.gd` and `godot/tests/p2_perf_a_n154_commission_owned_stage.gd`.
- Path: N154 funded construction commission, former `_copy_world("L3351", true)`.
- New stage: shallow World root plus deep detached `construction_sites`, `construction_contracts`, `faction_treasuries`, `contract_board`, `escrow_balances`, `construction_receipts`. All six are mutated by the same successful commission transaction. Other domains stay read-only; no mutable writer aliases to them in this function.
- Preserved: existing `Schema.validate`, `Schema.accounts`, N9 fork/escrow and total-conservation oracle, atomic World/Ledger publication and receipt identity. No changes to N158, N9 or ship/dock callers.
- Test: deep World oracle equality; rejection/source isolation; nested contract/site alias negative control.
- **CODE_COMMITTED · CODE_UNVERIFIED · TEST_ADDED_NOT_RUN**. No Godot execution or CI on this change; no measured CPU improvement or same-seed parity claim. N154 may be infrequent and is not proven to explain late-tick degradation.
- Next: run targeted N154 test and actual funded-commission positive/negative integration; N38 restart; compare same-seed early/late paid-tick p95 and deep-copy site counts with full N9/N39/contract/cargo oracle. Then prioritize the remaining *frequent* N39 copy sites (L4449/L4542/L4822/L4880/L4930) by measured call count, not by line number. No 2600-tick CI loop before targeted evidence.
