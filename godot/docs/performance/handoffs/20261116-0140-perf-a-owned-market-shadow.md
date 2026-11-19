# PERF A · N39 bounded market write-set shadow (2026-11-16)

- Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262.
- Code commit: `ee4db819016386f9e27b1b9d4cc46023b59126d7`.
- Test commits: `2412bc938e1a32367a02db170ff1895262d7cee6`, `7e3f81b9ca62de49a82fd03fccccbea133973ea4`.
- New helper: `godot/scripts/sim/phase1/n39_market_owned_write_guard.gd`.
- New targeted regression: `godot/tests/p2_perf_a_market_owned_write_guard_check.gd`.
- Bounded N150 observation write-set checks market cardinality, row shape, immutable non-observation fields (including nested physical stocks and credits), then delegates observation shape to existing N39 market observation validator. No authoritative state or ledger is mutated; no extra World, no runtime switch, no full Schema bypass.
- Negative cases: stock and credits mutation, extra row field, missing market, invalid price; unchanged and legal observation update. Full Schema.validate is explicitly checked against an incomplete World to demonstrate the local guard is **not** an authority.
- **CODE_UNVERIFIED / TEST_ADDED_NOT_RUN**: Godot 4.7.2 execution not available in this run. No measured speedup; helper remains isolated, no default production wiring.
- Next: owner A can add opt-in shadow invocation at the existing N150 observation commit boundary, using detached market dictionaries, and compare against full Schema.validate with a real paid-world fixture. Run parser, targeted test, N38 restart and 420/900 identical-seed checkpoints before considering an optimized authorization path. Do not change full production guard yet.
