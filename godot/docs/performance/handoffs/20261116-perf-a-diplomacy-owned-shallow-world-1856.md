# PERF A — isolated N39 diplomacy World copy (16 Nov 2026)

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

CODE COMMIT: `a1f5c536016f72d0112a89468d6581c355802f70`
TEST COMMITS: `86ae0bfc3dcf7c7740281089bf7ffd5767a23550`, `1ce5b8e2e03e5846394c873ac5fb07728e7954e6`

Files:
- `godot/scripts/sim/phase1/n39_native_world_production.gd`
- `godot/tests/p2_perf_a_diplomacy_owned_shallow_world_20261116.gd`

Two due-only N39 source stages (`apply_native_body_territory`, `apply_native_faction_relations`) previously deep-copied the **entire** growing World at copy sites `L5034` and `L5070`. They only replace a fully detached `body_territory` or `faction_relations` dictionary and a scalar last-tick field. Switched to shallow World header copy, retaining deep detachment of changed domains, full Schema.validate, Schema.accounts equality, and atomic _world publication. The other shared domains are read-only throughout these functions. No new authority, cache, or mutable alias escapes.

The regression builds a real frozen-seed N39 World, validates a detached shallow stage against the full Schema oracle and N9 accounts, checks invalid-domain rejection, checks source isolation and unchanged authoritative checkpoint. Runtime path still requires same-seed late/early parity including N38/BT/RNG/contract/cargo before acceptance.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED. No Godot execution or measured speedup. Affected copies are due-only and are not proven to explain the high-frequency `deep:L129` world_snapshot caller (2,929 calls / 34.66 s at ticks 601–900). No CI triggered.

NEXT: Coordinate with C to identify the precise ships/dock_queue callers of `world_snapshot()`, including intervening writes and ownership, before proposing an immutable bounded view; run bounded same-seed early/late profile and full parity gate.
