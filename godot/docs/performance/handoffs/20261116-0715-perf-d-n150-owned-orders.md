# PERF D — N150 retained order copy boundary (2026-11-16 07:15 MSK)

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.
Code commit: `8dd0cc400fc50a3291e4f001944c8ee4e61fb285`.
Test commit: `6657a88afc492c12d80d0a81072297ebd7a8e0d5`.

## Change
- `godot/scripts/sim/phase1/n150_native_full_market_tick.gd`: `tick_one_market` already duplicates the entire market deeply; `_retain_orders` now reuses its owned retained order rows rather than deep-copying each again. Default direct helper calls still detach retained orders.
- `godot/tests/p2_perf_d_n150_order_copy_oracle.gd`: checks old/new order equality and order, expiry, legacy filtering, nested mutable isolation of public helper and owned stage, invalid row rejection.

No changes to pricing, cadence, expiry, tie-break, World/N9/N158/N38 or receipt handling. No new runtime or persistent index.

## Verification
Static source/signature check: completed against current N150 source and existing `res://scripts/sim/phase1/n150_native_full_market_tick.gd`.
Godot test: **NOT RUN** (no local Godot); **CODE_UNVERIFIED / TEST_ADDED_NOT_RUN**.
Performance benefit: **NOT MEASURED**. Removes one redundant nested duplicate per retained order in N150's already-owned market stage; not a claim of FPS/TPS gain.
Actions: not triggered.

## Next
Run targeted oracle in Godot 4.7.2; compare full market snapshots, prices, order sequences and N38 restart with identical seed/cadence. Profile N150 market time over 420/900 ticks; revert if no measurable win or any parity difference. No lease held; files released.
