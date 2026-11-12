# N155 — Macro #7: faction director, native HTN, GOAP and read-only planning bridge

**Phase 1: CODE_UNVERIFIED / MACRO7_PARTIAL_SOURCE_PORT.** The full macro cannot be marked SOURCE-COVERED while another agent owns unfinished N100 hybrid.rs. These are source-backed standalone components, not a running Godot strategy tick.

## Reservation, references, coordination

- Exclusively reserved N155 on shared feature/godot-nightshift-20261112, commit 99d87478c0e57802fc27a771d53b2c9d4e94ea1d, BEFORE new source code.
- Work branch: feature/godot-n155-macro7-director-native-strategy-20261113, based on integration/godot-47-n33-n37-20261112.
- Frozen Rust reference: archive/rust-galaxy-067-reference @ 6e40615be95cc6ddbabe21c3b94def5c52f8622d.
- N100 claim status IN_PROGRESS, owner second-chat-overnight, work branch feature/godot-n100-hybrid-planner-overnight11, PR #188 PARTIAL. N155 neither modified nor claimed hybrid.rs.

## Real source-to-code mapping

| Native Rust source | New GDScript file | Transferred mechanics |
|---|---|---|
| strategy/director.rs: Profile.from_personality, record, observe and option_score | n155_director_native_observation.gd | Six real leader archetypes; weighted industry/science/caution/expansion, native household Food/Water crisis observations, stations, Paid contract counts, 100-row log, positive-benefit option utility. Research selection and paid shifts stay exclusively N143. |
| strategy/planning/native_catalogue.rs: projectable_stock, catalogue | n155_native_catalogue.gd | Separate owned market identities, facility-owned stock, Posted/Accepted commitments subtracted only from read-only projection, physical recipe inputs/outputs in real co-located producer, 17 original commodities and fallback prices, direct delivery with genuinely available carrier, size-10/20 and real ingredient lots, 120-tick / 1600 CR transport estimate, backwards dependency closure, stable sort/dedup. |
| native_catalogue.rs: pinned_producer_recipe, promote_industry_output_goal, comparison_case, projected_native_target, native_candidate_with_target | n155_native_catalogue.gd | Pinned producer/recipe/market validation, Food/Water demand-shortage output preference, no changing retry absolute stock milestone, 350-node/12-depth HTN candidate boundary. hybrid_native_candidate_with_target stays owned by N100's real hybrid planner. |
| planning/htn_adapter.rs: domain_from_native, NativeAction.apply | n155_native_domain.gd | Exact per-location integer stock fields, treasury-floor spendable cash, finite i32 checks, no merged markets, one departure per parked ship, no committed ship reuse, pinned authentic recipes and exact prerequisite/effect vectors. No imaginary stock/credit grant. |
| htn_adapter.rs: MethodSearch and bounded stock planning | n155_htn_methods.gd | Require/Prepare/Apply native recursion, missing-prerequisite search and ranking, cycle/100-task/depth/node bounds, stock/cash replay and ordered receipt-shaped steps. Crucial exception: the upstream Rust HTN 0.2.1 library final verification was NOT executed; upstream_htn_verified=false, native_dispatch_authorized=false. |
| planning/telic_goap.rs and forward_search.rs GOAP mode | n155_telic_goap_shadow.gd | Telic Boolean guide format limits (36 actions, 8 preconditions, 96 facts), native global cheapest-first stock/cash search and guarded optional upstream hints, cost-dominant ranking; not N99 16-width Beam. External upstream Telic plan_with NOT run or simulated. |
| planning/mod.rs: validate_plan | n155_planning_validation.gd | Shared plan schema/goal/depth/nodes/step identity/ordered dependencies/known action/forecast/cost/floor validator; an internally coherent plan is still not a physical receipt or executive authorisation. |
| planning/baseline.rs: goal_from_head, native_first_actions, diagnostic baseline; native_catalogue.rs: htn_native_shadow, native_candidate | n155_head_strategy_shadow.gd | N134 real HeadDecision converted into read-only goal and only native ready first actions; real physical HTN probe, baseline/validator snapshots, never submits an order or changes head decision. N117 planner comparison remains separate. |
| Native tests: non-creation invariants and source negative branches | n155_source_checks.gd | 14 source-derived fixtures AUTHORED, NOT RUN: no market fusion, leased cargo, fake funding, NaN physical stock, double reservation, forged plan or speculative dispatch. |

## Existing exclusive component owners — DO NOT run twice

- N19 and N134 PR #223: original coordination.rs, head candidate vote, player grant and one authorised action.
- N113 PR #202: director.retain_or_switch strategic hysteresis and commitment memory.
- N106 PR #195: durable production objectives from long_term.rs.
- N107 PR #196: station administrator and workforce needs.
- N93 PR #181: partial prior HTN BFS. N155 source-native domain/method projection REPLACES the earlier incompletely source-covered HTN algorithm; never tick both.
- N98 PR #186: durable execution ledger, no independent N155 plan ID/wallet state.
- N99 PR #187: Control Beam forward search, not the GOAP global search above.
- N100 PR #188: ACTIVE, IN PROGRESS, hybrid.rs with actual remaining ingredient decomposition and exact HTN/GOAP/Beam bounded arbitration — do not steal it.
- N117 PR #206: read-only planner comparison; N121 PR #216: authoritative native paid execution and receipts.
- N135 PR #225 and N152 PR #241: real station orders and ContractBoard. N143 PR #233: real paid research, mandates, progress. N154 PR #243: construction, paid shipyard and sites. N39: economy workforce/real production, excluded here.

## Mandatory Phase2 joining, not Phase1 scope

1. N134 authoritative HeadDecision and N113 retained strategy use ONE immutable native World/Board/market/ship snapshot, populated from real components and stable market IDs. N155 projection does NOT invent market stock, route or a carrier.
2. Run N155 native catalogue and exactly one planner per requested mode: native HTN domain/method, exact GOAP projection, N99 Beam or N100 full Hybrid after its owner's completed source transfer. N117 comparison can see all of these but cannot authorise the native ledger.
3. N155 HTN method search cannot truthfully claim the Rust upstream htn 0.2.1 primitive-task plus Sequence verification without executing that library or a proven exact differential test. Telic 0.1.0 upstream GoapPlanner.plan_with hints also await verification. Preview status must remain non-dispatchable.
4. N121 alone checks live physical source stock, carrier, route, fuel, paid payroll, escrow and Board/ledger. Original N155 producer actions have forecast wage cost=0 because no quote — NOT an authorisation for free production. Actual N39 wages and material transactions occur only once on real native Apply.
5. Preserve Director + N98 ledger + N121 receipts and real stock in one durable save/replay authority. Verify f32 vs f64, i32/i64/u64 limits, HashMap tie edge-cases during Rust/Godot parity tests; no P1 checkpoint/production/live save touched in N155.

## Honest remaining Macro 7 work

Full strategy/planning/hybrid.rs remains N100's IN_PROGRESS exclusive source scope: compose_ingredient_route, full HybridPlanner.decide, real HTN/GOAP/Beam comparison/arbitration, shared bounded budgets and actual candidate replay. N155 cannot close this or overwrite its claim. External upstream HTN/Telic execution verification and integrated Godot world adapters are Phase2 requirements, not hypothetical source parity. Additional source discrepancies if discovered during replay must be reopened explicitly.

**Current:** N155 CODE_UNVERIFIED; Macro #7 still PARTIAL SOURCE (N100). Existing seven SOURCE-COVERED directions: #2, #3, #4, #5, #6, #8, #9. Remaining source directions #1, #7 and #10. This is NOT a verified game, nor a percentage of completed Godot runtime.
