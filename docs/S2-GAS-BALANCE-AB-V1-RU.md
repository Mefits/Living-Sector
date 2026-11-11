# Gas balance A/B v1 — isolated experiment, not yet approved for production

## Verified native observations

Read-only source: https://github.com/Mefits/Living-Sector/actions/runs/43042995650 (SUCCESS), based on the 1250-tick real x16 Windows Genesis S2 run https://github.com/Mefits/Living-Sector/actions/runs/43038799967.

- Actual Huge Hauler hold capacity from ship report: 2000 units; gas purchases on real trades: 50 or 100 units. Only 2.5–5% of the hold went to that shipment.
- Alpha gas market fell from 6000 (tick 7) to 456 (tick 1250): net loss 5544 despite any existing mining, processing and trading. This number is the combined NET change, NOT isolated industrial consumption, and includes test-only initial inventory.
- Earth gas market at tick 1250 was 0, with shortage_ticks 384; three real gas deliveries totalling 200 were observed earlier, so stability was not established.
- Source rich-mining rate 80 units × richness per cycle is NOT changed. Lowering the global mining rate before comparing gross extraction and consumption could exacerbate existing scarcity.

## A/B proposal (changes only in experimental branch)

1. Only two gas-using refinery recipes (fuel cracking and polymer production) change: gas input 6 → 5 per batch, output unchanged. Exact per-batch gas demand is 16.7% lower. Recipe execution still needs physical inputs and paid labor; zero inputs yield zero output.
2. All non-gas delivery orders keep their current quantity curve: base 50, +25 per 30 shortage ticks above 30, max 200. Early gas orders also retain base 50.
3. Only chronic recipe-input GAS shortages grow more rapidly: gas 50 at 30 ticks, 100 at 60, 150 at 90, 300 at 180 and cap 400. A normal Medium Freighter has capacity 500 and a Huge Hauler 2000; this is still not an enforced guarantee that a free ship exists.
4. Increases apply ONLY when a genuine source market stocks the full order and the requester can fund at least the existing 40 credits-per-unit floor. The desired lot automatically falls back in 25-unit increments all the way to the original 50-unit gas starter lot if inventory or credits are too low; other commodities preserve their old shortage-size unchanged. This was caught by a native regression: a payer able to afford 150 gas must not be rejected just because the chronic-shortage curve otherwise demanded at least 175. No free supplies, no fabricated money, no bypass of diplomacy or ship fittings.
5. All global mining output, normal route geometry, engine physics, default colony population food/water use, research, modules and unchanged player saves are untouched.

## A/B acceptance gates

CI https://github.com/Mefits/Living-Sector/actions/runs/43044057840 must verify Rust regressions, build Windows Genesis directly from native source, run a single 1250-tick game on the SAME test-only physical geometry (Alpha 4,0 / nominal lane 1), then compare with the existing baseline artifact from run 43038799967. It must separately report exact native gas receipt quantity, Earth shortage count/positive stock observations, Alpha remaining gas, and whether new production causes unintended shortages.

This is ONE seed, one shortened test geometry. Even if improved, it DOES NOT prove default-world sustainable economy, repeated-crisis resilience, save compatibility or full food/water support. Do not automatically merge this branch to main or stable. If variant worsens logistics or exhausts payer funds, reject it or adjust after inspecting native evidence.

## Actual A/B results (complete, 11 Nov 2026)

- [Direct-source Windows real S2 x16 A/B CI #43045539397](https://github.com/Mefits/Living-Sector/actions/runs/43045539397) SUCCESS: 4/4 focused Rust tests, Windows server release, one full genuine 1250-ish tick replay, archived evidence.
- Original baseline #43038799967: last tick 1250; native gas deliveries 3, units 200; Earth final gas 0; shortage_ticks 384; Alpha gas 456; 2 positive-stock Earth snapshots.
- Combined experiment: last tick 1271; native gas deliveries 3, units **400**; Earth final gas **0**; shortage_ticks **489**; Alpha gas 528; 0 positive-stock Earth snapshots. More cargo was delivered, but sustainable gas availability is NOT proven and the duration/sampling windows differ slightly.
- Run verdict: delivery_verified=true, relief_verified=false, resilience_verified=not_tested. The CI is green because it proves the scenario ran and the comparison can be computed, NOT because the balance is accepted or improved.

[Independent downstream materials audit #43047668057](https://github.com/Mefits/Living-Sector/actions/runs/43047668057) SUCCESS, reuses saved raw native data and does not rerun the simulation:
- Alpha final: gas +72 vs baseline; fuel +851; polymers +771; water +50; food unchanged; components -78.
- Earth final: gas unchanged at 0; fuel +26; polymers 0 both; **water -572, metals -1052, components -79**, food unchanged.
- These are **net inventories**, not direct per-recipe production counters. One seed and a slightly longer variant cannot establish causality or long-run equilibrium.

**Decision: DO NOT PROMOTE THE COMBINED TWEAK.** Keep PR #70 in draft. Splitting gas-recipe input changes and gas-contract quantity scaling into **two isolated, comparable experiments** is required before accepting any coefficient. Do not reduce mining globally (Alpha source inventory already falls steeply in both tests). Do not change ordinary goods, ship sensors, wallet rules or the production map on this evidence. Next gate also checks station payer balances and fuel/polymer/food/water, not just gas delivered.
