# PERF C · N14 advance owned-fleet boundary · 17.11.2026 11:21 MSK

- CODE COMMIT: cdbfbdb14dc5dd5e27fff5f5de81f22e8934310e
- TEST COMMIT: 51a19b5ef463b6d1852bd922d094d2726e7b973b
- FILES: `godot/scripts/sim/phase2/unified_ship_phase.gd`; `godot/tests/p2_perf_c_n14_owned_advance_no_second_fleet_copy_20261117.gd`.
- WHY: `N140Gate.stage()` creates `out = world["ships"].duplicate(true)` and `state.ships = gate["ships"]` before N14 motion. On changed paid ticks, `advance()` subsequently deep-copied every row of that already detached fleet into `updated`. Return the exclusively owned `state.ships` instead; avoid second O(fleet nested bytes) copy. The N39 authoritative World remains detached; N14 still validates all movement and fuel, and no ledger/BT/RNG decisions changed.
- NEGATIVE: executable test uses real N140.stage and nested cargo/memory/BT mutation oracle plus N14 return-source boundary. This test is NOT a substitute for actual moving-ship, N38 and full same-seed parity.
- TEST EXECUTED: NOT RUN. CODE_UNVERIFIED; no Godot runtime or CI invoked. Runtime savings NOT MEASURED.
- NEXT: run targeted test and moving-ship fuel/cargo oracle; compare same-seed paid tick100/600/900 ship+dock CPU avg/p95, phase/site calls and growing structure sizes; exact N9/N39/N38/BT/RNG/contract parity. If downstream caller mutates returned preview outside exclusive ownership, revert or detach at caller boundary. Do not duplicate 99ab25e9 / 1676db61.
