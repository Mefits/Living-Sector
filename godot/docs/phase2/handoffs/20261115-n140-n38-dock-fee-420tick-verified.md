# Living Sector — verified N140/N38 ship+save repair (15 Nov 2026)

**Branch:** `integration/godot-phase2-unified-20261113` (PR #249).
**Real official Godot 4.7.2 CI PASS:** https://github.com/Mefits/Living-Sector/actions/runs/43663200299
**Tested SHA:** `6005f86fc61a287bb6e214f5851cf5e3c9b312c0`
**Scope:** Source-faithful N140/N84/N146 read-only planning optimization plus exact N21/N38 paid dock receipt restoration. No balance, player mechanics, speculative ship departures or economy gates changed.

## Original user blockers (already solved before this block)

The earlier `n97_service_not_a_mining_waypoint` and `n21_n21_invalid_staged_source_world` refusals were fixed in preceding commits; authentic 240-tick CI showed 11 N14 departures, 9 cargo transfers and 6 N21 docking events. This is **not** proof of an autonomous paid N104 delivery cycle. Source audit: `20261115-fleet-performance-first-audit.md`.

## This block's changes

- `7caeb831e`: N140 forwarder no longer deep-clones the whole N39 World and each active ship right before N84's own detached deep copy. Outer map shallow-copied, source actors read-only, N84 owns mutation, returned ships detached.
- `e3dfc6ea6`: independent Godot 2-ship source parity regression proves same N84 trace/N146 ReleaseDock, no mutation of sleeping ship, live World, or returned aliases.
- `8f463fc8e`: parity regression wired into one unified smoke.
- **Original full-test FAILURE:** https://github.com/Mefits/Living-Sector/actions/runs/43662514701 — parser, source economy, N143 research, N91, N38 f64 and N140 parity all PASS; full stage2 reached tick360 but N38 save could not restore.
- **Root cause:** N151 temporary marketless dock now legitimately earns paid N21 fees; its strict provenance validator `_original_colony_dock_income_proved` checks each dock receipt `fee` has `TYPE_INT`. After JSON reload N158 normalized `dock_receipts.tick` but **not `dock_receipts.fee`**, so even integer-shaped float receipts failed N39 Schema. Never relax source proof.
- `5996801d8`: N158 N38 restore now converts **only exactly integral** existing N21 `fee` fields; still rejects fractional and nonnumeric amounts, preserving N151 source receipt/N9 money checks.
- `672f4f4e6`: adds fail-closed N38 tick360 diagnostic with isolated read-only timeline, serialized coherence, native normalization, world schema, and N39 restore status if regression returns.
- `acafc87a6`: codec-only regression checks exact `fee/tick` conversion, rejects fractional/text fees, and proves live World unchanged.
- `6005f86fc`: one final real unified smoke with both regressions and bounded 300s full-world scenario (previous 180s bound was too tight for measured 420-tick workload).

## Verifiable real Godot 4.7.2 results (run 43663200299)

- `P2_UNIFIED_PARSE_SCAN: loaded=310 total=310 failures=0`
- `P2_N140_N84_SHALLOW_FORWARDING_SOURCE_PARITY_PASS`
- `P2_N38_N21_FEE_INTEGER_ROUNDTRIP_PASS`
- `P2_UNIFIED_ECONOMY_ACCEPTANCE_PASS`
- `P2_GATE4_ORIGINAL_N143_PAID_RESEARCH_N9_SAVE_PASS`
- `P2_N91_SOURCE_N151_MARKETLESS_RECEIPTED_DOCK_PASS`
- `P2_N38_NATIVE_F64_EXACT_JSON_ENVELOPE_PASS`
- `P2_STAGE2_CLEAN_NATIVE_TICK420_N38_RESTART_PASS elapsed_ms=199932`
- Original clean seeded World, no manual movement, injected orders or artificial goods. At tick360 save/restore PASS; tick361 PASS; tick420 PASS; ships=24, contracts=2, N9 receipts=2189, documented wage/removal sinks=4920, spendable credits=2755080.

## Unresolved work / next macroblock

1. **Performance is still poor:** 199.9 seconds wall time for 420 native ticks in the test, cumulative timing ~56.5s at tick240, ~158s at tick360. N140 forwarding is only a small isolated optimization. Profile late N146 paid dock/command apply and N39 World + N9 receipt validation, then optimize without changing Rust mechanics. Measure before/after and long soak, not speculative UI tuning.
2. **Clean autonomous N104 end-to-end delivery is NOT verified** despite 2 real contracts and earlier real departures. Need source-paid Head→N104→N153→N84/N14→N21→N97/N15→N9 completed freight with one physical receipt/payout, no scripted ship orders. Preserve all failure gates.
3. User's Windows F5/real GUI performance and 10k-tick soak not verified. The CI test is a bounded headless integrated sim check, not a guarantee of smooth client FPS.

Do not regress paid N21/N151 fee proof, N38 strict save roundtrip, source LOD semantics or single N39/N9 owner. Avoid excessive repeated Actions; source code and a single targeted CI run per meaningful batch.
