//! Ship decision-making — planner, BT builders, and their helpers.
//!
//! This module hosts everything between "tick observed the world"
//! (handled by `ship/mod.rs`'s tick passes) and "the dispatched
//! action runs" (handled by `actions.rs`'s ShipAction executor):
//!
//!   * **Planner core** — [`decide_and_act`] is the per-ship inner
//!     loop, called by `tick_ships` for each ship that's awake this
//!     tick. It coordinates replan checks, runs the active BT until
//!     it terminates, and on terminate calls [`plan_goal`] to pick a
//!     new goal + matching BT.
//!   * **Goal scoring** — [`plan_goal`] / [`score_strategic`] +
//!     [`is_replan_eligible`] implement the unified utility scorer
//!     that replaced the old priority-waterfall in Bundle 2.1.
//!   * **Plan helpers** — [`try_plan_contract`] / [`try_plan_trade_run`]
//!     produce candidates with profit estimates that `plan_goal`
//!     scores. [`best_trade_route`] consults the ship's price memory
//!     (with freshness decay + route-performance penalty) to find a
//!     viable trade run.
//!   * **Idle / explore** — [`smart_idle_fallback`] +
//!     [`try_build_explore_bt`] — when no contract or trade run is
//!     viable, ships escalate from sitting still into exploring an
//!     adjacent system they haven't been to lately.
//!   * **Rest / retrofit** — [`pick_rest_destination`] picks a
//!     congestion-aware shore-leave target; [`find_retrofit_opportunity`]
//!     scans for a reachable shipyard with a desired-tier module
//!     in stock.
//!   * **BT builders** — `build_*_bt` and `try_build_*_planned`
//!     produce the BTs the planner returns. The hand-authored
//!     `build_*_bt` shims now just call their planner counterparts;
//!     when the GOAP planner can't synthesise a plan (extremely rare,
//!     never observed in prod), they fall back to `BtNode::action(Idle)`
//!     and let the next tick replan.
//!   * **Combined goals** — `try_build_*_with_retrofit_planned`
//!     interleave a shipyard detour into a delivery / trade-run plan
//!     when the ship has retrofit points + a reachable upgrade.
//!
//! Every BT builder is parameterised over abstract `Loc` symbols
//! (Origin / Source / Dest / Shipyard) that the GOAP planner solves
//! against; [`compile_plan_to_bt`] flattens the synthesised action
//! sequence back into a runnable BT.
//!
//! Extracted from `ship/mod.rs` in the Phase-21 god-module split.

use crate::ai::behavior_tree::BtNode;
use crate::economy::commodities::Commodity;
use crate::simulation::commands::{CommandBuffer, SimCommand};
use crate::world::registry::WorldRegistry;
use std::collections::HashMap as StdHashMap;

use super::actions::ShipAction;
use super::*;


/// Find the best profitable trade route from memory.
/// Result of a successful trade-run plan — parallel shape to
/// [`ContractCandidate`] so `plan_goal` can score the two options
/// against each other via the ship's personality. Phase 18i.
pub struct TradeRunCandidate {
    pub profit: i64,
    pub bt: BtNode<ShipAction>,
    /// Raw trade-run params so callers can re-synthesise a combined
    /// trade_run+retrofit BT without re-computing `best_trade_route`.
    pub buy_loc: String,
    pub sell_loc: String,
    pub commodity: Commodity,
}

/// Try to build a trade_run BT + estimate its profit. Returns `None`
/// when no margin-positive route exists in the ship's price memory.
#[allow(clippy::too_many_arguments)]
fn try_plan_trade_run(
    at_loc: &str,
    memory: &ShipMemory,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    current_tick: u64,
    fuel_bucket: u8,
) -> Option<TradeRunCandidate> {
    let (commodity, buy_loc, sell_loc, _margin) = best_trade_route(memory, current_tick)?;
    let buy_price = memory
        .price_knowledge
        .get(&buy_loc)
        .and_then(|m| m.get(&commodity))
        .map(|p| p.price)
        .unwrap_or(1.0);
    let sell_price = memory
        .price_knowledge
        .get(&sell_loc)
        .and_then(|m| m.get(&commodity))
        .map(|p| p.price)
        .unwrap_or(0.0);
    let profit = ((sell_price - buy_price) * TRADE_QTY_DEFAULT as f32).round() as i64;
    let bt = build_trade_run_bt(
        at_loc,
        &buy_loc,
        &sell_loc,
        commodity,
        fuel_bucket,
        registry,
        gate_pairs,
    );
    Some(TradeRunCandidate {
        profit,
        bt,
        buy_loc,
        sell_loc,
        commodity,
    })
}

/// Phase 19h: median of every remembered price for `commodity`
/// across the ship's `price_knowledge`. Used by `try_plan_contract`
/// as a "reasonable guess" when the ship has never observed the
/// contract's source location directly. Returns None when the ship
/// has no memory of this commodity anywhere — then the planner
/// falls back to skipping the contract.
pub fn median_known_price(memory: &ShipMemory, commodity: Commodity) -> Option<f32> {
    let mut prices: Vec<f32> = memory
        .price_knowledge
        .values()
        .filter_map(|m| m.get(&commodity).map(|p| p.price))
        .collect();
    if prices.is_empty() {
        return None;
    }
    prices.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let mid = prices.len() / 2;
    Some(prices[mid])
}

pub fn best_trade_route(
    memory: &ShipMemory,
    current_tick: u64,
) -> Option<(Commodity, String, String, f32)> {
    let mut best: Option<(Commodity, String, String, f32)> = None;
    let locs: Vec<_> = memory.price_knowledge.iter().collect();
    for (i, (loc_a, prices_a)) in locs.iter().enumerate() {
        for (loc_b, prices_b) in locs.iter().skip(i + 1) {
            for (commodity, pa) in prices_a.iter() {
                if let Some(pb) = prices_b.get(commodity) {
                    let (buy, sell, lo, hi) = if pa.price < pb.price {
                        ((*loc_a).clone(), (*loc_b).clone(), pa.price, pb.price)
                    } else {
                        ((*loc_b).clone(), (*loc_a).clone(), pb.price, pa.price)
                    };
                    // Bundle 1.2: freshness decay — discount routes
                    // whose endpoint prices are stale. The route is
                    // only as fresh as the older of its two
                    // observations, so use the minimum of the two
                    // weights.
                    let freshness = price_freshness_weight(pa.tick, current_tick)
                        .min(price_freshness_weight(pb.tick, current_tick));
                    let raw_margin = (hi - lo) / lo.max(1.0) * freshness;
                    // Phase 20: discount the margin when this ship's
                    // actual history on (buy → sell, commodity)
                    // underperforms what the current prices project.
                    // After 3 attempts we trust the learned average;
                    // if it's < 50% of the projected per-unit gap we
                    // apply a strong (0.3×) penalty so the ship drifts
                    // toward less-saturated routes. Ships with no
                    // history keep the full raw margin — nothing
                    // penalises an untried route.
                    let expected_per_unit = hi - lo;
                    let learned_mult = memory
                        .route_performance
                        .get(&(buy.clone(), sell.clone(), *commodity))
                        .and_then(|stats| {
                            if stats.attempts < 3 {
                                return None;
                            }
                            let avg = stats.avg_profit_per_unit();
                            if avg < expected_per_unit * 0.5 {
                                Some(0.3_f32)
                            } else {
                                Some(1.0_f32)
                            }
                        })
                        .unwrap_or(1.0);
                    let margin = raw_margin * learned_mult;
                    if margin > MIN_TRADE_MARGIN && best.as_ref().is_none_or(|b| margin > b.3) {
                        best = Some((*commodity, buy, sell, margin));
                    }
                }
            }
        }
    }
    best
}

/// Pass 3: decide + act on each ship.
#[allow(clippy::too_many_arguments)]
pub(super) fn decide_and_act(
    world: &mut hecs::World,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    contracts: &crate::economy::contracts::ContractBoard,
    relations: &crate::agents::faction_relations::FactionRelations,
    commands: &mut CommandBuffer,
    tick: u64,
    tick_multiplier: u32,
    active: &ShipLodGate,
) {
    let config = crate::simulation::config::TickConfig {
        ticks_per_second: 8,
        world_speed: if tick_multiplier == 0 { 0.25 } else { 8.0 / tick_multiplier as f32 },
    };

    // Phase 18f: one location → system name index, used by
    // - shipyard inventory tagging (retrofit proximity)
    // - cross-system contract gating in try_plan_contract
    let location_to_system: std::collections::HashMap<String, String> = {
        use crate::agents::celestial_body::BodyIdentity;
        let body_db_to_system: std::collections::HashMap<i64, String> = world
            .query::<&BodyIdentity>()
            .iter()
            .map(|(_, id)| (id.db_id, id.system_name.clone()))
            .collect();
        registry
            .locations
            .iter()
            .filter_map(|(name, info)| {
                let sys = body_db_to_system.get(&info.celestial_body_id)?;
                Some((name.clone(), sys.clone()))
            })
            .collect()
    };

    // Phase 18L: per-location dock congestion snapshot.
    // `(total_capacity, total_docked_count, total_queued_count)`
    // summed across every non-gate facility at the location. Used
    // by the congestion-aware rest planner so ships with low
    // morale don't route to a fully-saturated station when a
    // nearby one has space.
    //
    // Post-tick-21k-spiral fix: queue length is tracked alongside
    // docked count so a station with 25/25 docked + 44 queued is
    // recognized as saturated even though the literal dock count
    // equals capacity. Without this, `pick_rest_destination` saw
    // "docked==cap" only when docks were exactly full, ignoring
    // the massive queue pressure, and 170+ ships piled onto the
    // same over-full station.
    //
    // Read-only; built once per call. Gates are excluded (they're
    // not meant to host resting crews).
    let dock_congestion: std::collections::HashMap<String, (u32, u32, u32)> = {
        use crate::agents::facility::{
            FacilityIdentity, FacilityLocation, FacilityOperations, FacilityStorage,
        };
        let mut out: std::collections::HashMap<String, (u32, u32, u32)> =
            std::collections::HashMap::new();
        for (_e, (id, loc, ops, storage)) in world
            .query::<(
                &FacilityIdentity,
                &FacilityLocation,
                &FacilityOperations,
                &FacilityStorage,
            )>()
            .iter()
        {
            if id.facility_type == "gate" || ops.docking_capacity == 0 {
                continue;
            }
            let entry = out.entry(loc.location_name.clone()).or_insert((0, 0, 0));
            entry.0 = entry.0.saturating_add(ops.docking_capacity);
            entry.1 = entry.1.saturating_add(storage.docked_ships.len() as u32);
            entry.2 = entry.2.saturating_add(storage.dock_queue.len() as u32);
        }
        out
    };

    // Bundle C: market-controlling faction per location. Majority of
    // facility count at each location wins (tiebreak: first-seen).
    // A market's controller governs the posture multiplier applied
    // to every Buy / Sell at that location, so prices for a given
    // ship depend on their personal rep with this faction.
    //
    // Built once per tick because facility ownership changes on the
    // construction-completion + admin-delete paths (rare) and a
    // per-ship rebuild would be wasteful.
    let controller_by_location: std::collections::HashMap<String, String> = {
        use crate::agents::facility::{FacilityIdentity, FacilityLocation};
        let mut counts: std::collections::HashMap<String, std::collections::HashMap<String, u32>> =
            std::collections::HashMap::new();
        for (_e, (id, loc)) in world
            .query::<(&FacilityIdentity, &FacilityLocation)>()
            .iter()
        {
            if id.faction_id.is_empty() {
                continue;
            }
            *counts
                .entry(loc.location_name.clone())
                .or_default()
                .entry(id.faction_id.clone())
                .or_insert(0) += 1;
        }
        counts
            .into_iter()
            .filter_map(|(loc, per_faction)| {
                let winner = per_faction
                    .into_iter()
                    .max_by_key(|(_, n)| *n)
                    .map(|(fac, _)| fac)?;
                Some((loc, winner))
            })
            .collect()
    };

    // Phase 18d: snapshot shipyard inventories once per call so per-ship
    // retrofit planning doesn't re-query hecs. Each entry is (location,
    // system_id, slug → qty). Skipping abandoned shipyards matches the
    // existing "abandoned facilities don't service ships" pattern. The
    // system tag lets `find_retrofit_opportunity` prefer same-system
    // yards so Tau Ceti ships don't fly across gates for a tier-2
    // engine when their local Anvil yard has one in stock.
    let shipyard_inventory: ShipyardInventorySnapshot = {
        use crate::agents::facility::{
            FacilityIdentity, FacilityLifecycle, FacilityLocation, ModuleStock,
        };
        world
            .query::<(&FacilityIdentity, &FacilityLocation, &FacilityLifecycle, &ModuleStock)>()
            .iter()
            .filter(|(_, (id, _, life, _))| id.facility_type == "shipyard" && !life.abandoned)
            .map(|(_, (_, loc, _, stock))| {
                let system = location_to_system
                    .get(&loc.location_name)
                    .cloned()
                    .unwrap_or_default();
                (loc.location_name.clone(), system, stock.stock.clone())
            })
            .collect()
    };

    let entities: Vec<hecs::Entity> = world
        .query::<&ShipIdentity>()
        .iter()
        .map(|(e, _)| e)
        .collect();

    for entity in entities {
        // LOD gate — LOD'd-out ships don't replan or execute BT steps
        // this round. They'll pick back up on their next fire.
        if !active.contains_key(&entity) {
            continue;
        }

        // Fetch ship's string id (used for contract acceptance) +
        // faction id (used by Bundle B's treaty-implied rep floor).
        let (ship_id, ship_faction): (String, String) =
            match world.get::<&ShipIdentity>(entity) {
                Ok(id) => (id.id.clone(), id.faction_id.clone()),
                Err(_) => continue,
            };

        // Snapshot crew state before the main mut borrow (needed for the planner).
        let crew_snapshot: Option<ShipCrew> = world
            .get::<&ShipCrew>(entity)
            .ok()
            .map(|c| (*c).clone());

        // Phase 18d: compute a retrofit opportunity before the main mut
        // borrow. Requires a banked retrofit point AND the usual
        // fitting + credits + stock gates. None if any check fails —
        // the ship will plan normally.
        let retrofit_plan: Option<RetrofitPlan> = (|| {
            let prog = world.get::<&ShipProgression>(entity).ok()?;
            if prog.retrofit_points == 0 {
                return None;
            }
            let fitting = world.get::<&ShipFitting>(entity).ok()?;
            let economy = world.get::<&ShipEconomy>(entity).ok()?;
            let position = world.get::<&ShipPosition>(entity).ok()?;
            let ship_location = position.location_name.clone().unwrap_or_default();
            let ship_system = position.system_id.clone();
            find_retrofit_opportunity(
                &fitting,
                &shipyard_inventory,
                economy.credits,
                &ship_location,
                &ship_system,
            )
        })();

        // Phase 18f: sensor range determines whether the contract
        // planner can see cross-system contracts. Read before the
        // main mut borrow so plan_goal doesn't need mutable access
        // to the fitting. Default to 0.0 for pre-18f ships (they'll
        // be treated as myopic and skip cross-system contracts).
        let sensor_range_au: f32 = world
            .get::<&ShipFitting>(entity)
            .map(|f| f.derived.sensor_range_au)
            .unwrap_or(0.0);

        let mut q = match world.query_one::<(
            &mut ShipPosition,
            &mut ShipTransit,
            &mut ShipCargo,
            &mut ShipFuel,
            &mut ShipEconomy,
            &mut ShipAI,
            &mut ShipMemory,
            &mut ShipLifecycle,
            &mut ShipCrew,
        )>(entity) {
            Ok(q) => q,
            Err(_) => continue,
        };
        let (position, transit, cargo, fuel, economy, ai, memory, lifecycle, crew) = match q.get() {
            Some(t) => t,
            None => continue,
        };

        if transit.transit.is_some() {
            // Keep `current_goal` as whatever the plan picked (e.g.
            // "fulfill_delivery") so the UI can show what the ship is
            // actually doing mid-flight. The BT's Travel node returns
            // Running, so we don't re-tick the BT here.
            continue;
        }

        // Sanity-clean stale active_contract_id before planning.
        // Covers three cases:
        //   1. The contract finalised (Paid / Expired) but the Deliver
        //      action never ran (BT ended before reaching it).
        //   2. A speculative-accept race: the ship set its id locally
        //      but another ship won the AcceptContract apply, so the
        //      contract's fulfiller_id isn't us.
        //   3. **Phase 19h**: ghost contract — status=Accepted, we're
        //      the fulfiller, but `current_bt = None` (BT finished
        //      early via Success without reaching Deliver). Without
        //      this branch the ship sits idle holding a contract
        //      nobody else can take. Release + clear so a re-planner
        //      picks it up fresh next cycle.
        //
        // In cases 1 + 2 we just clear locally (the contract is either
        // gone or not ours to release). Case 3 emits a
        // `ReleaseContract` so the board moves Accepted → Posted and
        // another ship can accept it.
        if let Some(cid) = economy.active_contract_id.clone() {
            enum StaleKind { Drop, Release, Keep }
            let kind = match contracts.get(&cid) {
                None => StaleKind::Drop,
                Some(c) => {
                    use crate::economy::contracts::ContractStatus;
                    let finalized = matches!(
                        c.status,
                        ContractStatus::Paid | ContractStatus::Expired
                    );
                    let not_ours = c.fulfiller_id.as_deref() != Some(ship_id.as_str());
                    let ghost = matches!(c.status, ContractStatus::Accepted)
                        && !not_ours
                        && ai.current_bt.is_none();
                    if finalized || not_ours {
                        StaleKind::Drop
                    } else if ghost {
                        StaleKind::Release
                    } else {
                        StaleKind::Keep
                    }
                }
            };
            match kind {
                StaleKind::Drop => {
                    economy.active_contract_id = None;
                    ai.current_bt = None;
                }
                StaleKind::Release => {
                    economy.active_contract_id = None;
                    ai.current_bt = None;
                    commands.push(SimCommand::ReleaseContract {
                        ship_id: ship_id.clone(),
                        contract_id: cid,
                        reason: "ghost_bt",
                    });
                }
                StaleKind::Keep => {}
            }
        }

        let needs_plan = ai.current_bt.is_none();
        // Bundle 2.2: mid-action replan check. If the current goal is
        // replan-eligible, we've been committed for the minimum dwell,
        // and it's this ship's check-interval tick, re-run the planner
        // and switch if the new top candidate clears the
        // REPLAN_SCORE_RATIO bar. Prevents ships from locking into
        // stale trade runs when a juicy subsidy lands mid-flight.
        //
        // Perf tune: the trigger used to be `tick % INTERVAL == 0`
        // which synced every eligible ship onto the same ticks and
        // created p99 spikes. Now each ship gets a per-id hash
        // offset so checks spread across all ticks evenly — same
        // overall check frequency, flatter CPU profile.
        let elapsed_since_plan = tick.saturating_sub(ai.last_plan_tick);
        let ship_offset: u64 = {
            // Cheap deterministic hash — FNV-style on the id bytes.
            let mut h: u64 = 14695981039346656037;
            for b in ship_id.as_bytes() {
                h ^= *b as u64;
                h = h.wrapping_mul(1099511628211);
            }
            h % REPLAN_CHECK_INTERVAL_TICKS
        };
        let replan_check_due = !needs_plan
            && is_replan_eligible(&ai.current_goal)
            && elapsed_since_plan >= REPLAN_MIN_COMMIT_TICKS
            && (tick + ship_offset) % REPLAN_CHECK_INTERVAL_TICKS == 0;

        if needs_plan || replan_check_due {
            // Bundle B: merge the ship's explicit reputation with
            // treaty-implied floors so a TradePact grants visibility
            // of the 50-rep tier, Allied grants 70. Merge max()s in
            // favour of explicit rep, so a heavily-decorated ship
            // doesn't get *downgraded* by a treaty with a lesser ally.
            let effective_reputation: StdHashMap<String, u8> = {
                let floors =
                    crate::agents::faction_relations::treaty_rep_floors(
                        relations,
                        &ship_faction,
                    );
                let mut out = economy.faction_reputation.clone();
                for (fac, floor) in floors {
                    let entry = out.entry(fac).or_insert(0);
                    if *entry < floor {
                        *entry = floor;
                    }
                }
                out
            };
            let candidate = plan_goal(
                position,
                cargo,
                fuel,
                economy,
                memory,
                crew_snapshot.as_ref(),
                contracts,
                &effective_reputation,
                &ship_id,
                registry,
                gate_pairs,
                retrofit_plan.as_ref(),
                sensor_range_au,
                &location_to_system,
                &ai.personality,
                &dock_congestion,
                lifecycle.idle_ticks,
                tick,
            );
            // Obligation-aware replan bar. A ship holding an active
            // contract treats it as a real commitment — the bar to
            // replace it rises by a fixed obligation weight plus a
            // personality-loyalty multiplier. Without this, the
            // scorer treated in-flight contracts as sunk cost and
            // dropped them for marginal improvements, which showed
            // up as a 43% contract breach rate in the Bundle-A
            // diagnostic. Honest replans for genuinely much-better
            // opportunities still fire.
            let effective_ratio = if economy.active_contract_id.is_some() {
                REPLAN_SCORE_RATIO
                    + CONTRACT_OBLIGATION_WEIGHT
                    + ai.personality.loyalty.clamp(0.0, 1.0)
                        * LOYALTY_REPLAN_MULTIPLIER
            } else {
                REPLAN_SCORE_RATIO
            };
            let accept = needs_plan
                || candidate.score >= ai.current_goal_score * effective_ratio;
            if accept {
                // Release any active contract we were committed to
                // before swapping plans — otherwise the ship can end
                // up with an active_contract_id that no current BT is
                // working. ReleaseContract apply phase tolerates
                // stale ids safely.
                if replan_check_due {
                    if let Some(cid) = economy.active_contract_id.take() {
                        commands.push(SimCommand::ReleaseContract {
                            ship_id: ship_id.clone(),
                            contract_id: cid,
                            reason: "replan",
                        });
                    }
                }
                ai.current_goal = candidate.name.into();
                ai.current_goal_score = candidate.score;
                ai.current_bt = Some(candidate.bt);
                ai.last_plan_tick = tick;
            }
        }

        // Phase 19h: track how long the ship has been in an idle-ish
        // state so the explore escalation fires at the right time.
        // Any goal starting with "idle" counts; anything else resets.
        // Using starts_with lets future variants ("idle_seek_station")
        // share the counter without manual enumeration.
        if ai.current_goal.starts_with("idle") {
            lifecycle.idle_ticks = lifecycle.idle_ticks.saturating_add(1);
        } else {
            lifecycle.idle_ticks = 0;
        }

        // --- Strike accumulation (adaptive-fleet retirement, Phase 19-tail) ---
        //
        // Evaluated on a slow cadence so a ship that briefly dips below
        // the credits floor doesn't take a strike on every tick. Strikes
        // reset when the ship recovers; 3 of either kind triggers
        // decommission via SimCommand::DecommissionShip (engine emits the
        // retirement row + queues a replacement spawn).
        let strike_interval = STRIKE_CHECK_INTERVAL_BASE * tick_multiplier as u64;
        if strike_interval > 0 && tick % strike_interval == 0 {
            // Broke strike: nothing to sell, no one paying us, no cash.
            let cargo_empty = cargo.used() == 0;
            let no_contract = economy.active_contract_id.is_none();
            if economy.credits < BROKE_CREDITS_THRESHOLD && cargo_empty && no_contract {
                lifecycle.broke_strikes = lifecycle.broke_strikes.saturating_add(1);
            } else if economy.credits >= BROKE_RECOVERY_THRESHOLD {
                lifecycle.broke_strikes = 0;
            }
            // Hoard strike: lots of credits, long idle window. Reset
            // happens on DeliverContract apply (see engine.rs).
            if economy.credits > HOARD_CREDITS_THRESHOLD
                && lifecycle.idle_ticks > HOARD_IDLE_THRESHOLD
            {
                lifecycle.hoard_strikes = lifecycle.hoard_strikes.saturating_add(1);
            }

            if lifecycle.broke_strikes >= MAX_STRIKES {
                commands.push(SimCommand::DecommissionShip {
                    ship: entity,
                    reason: "bankruptcy",
                });
            } else if lifecycle.hoard_strikes >= MAX_STRIKES {
                commands.push(SimCommand::DecommissionShip {
                    ship: entity,
                    reason: "stagnation",
                });
            }
        }

        // --- Execute one BT step ---
        if let Some(mut bt) = ai.current_bt.take() {
            let mut bb = Blackboard::new();
            let status = {
                let ship_id_ref = &ship_id;
                let ship_faction_ref = &ship_faction;
                let mut dispatch = |action: &ShipAction, bb: &mut Blackboard| -> BtStatus {
                    execute_ship_action(
                        action,
                        entity,
                        ship_id_ref,
                        ship_faction_ref,
                        crew,
                        position,
                        transit,
                        cargo,
                        fuel,
                        economy,
                        memory,
                        registry,
                        relations,
                        &controller_by_location,
                        commands,
                        tick,
                        &config,
                        bb,
                    )
                };
                bt.tick(&mut bb, &mut dispatch)
            };

            // Bundle 1.4: drift personality in response to BT events
            // surfaced via the blackboard. Only `rest_timed_out`
            // today; delivery-success drift happens in the engine
            // apply phase (direct world access on DeliverContract).
            if bb.get_bool("rest_timed_out") {
                ai.personality
                    .drift(crate::ai::personality::Axis::Safety, DRIFT_REST_TIMEOUT_SAFETY);
            }

            match status {
                BtStatus::Running => ai.current_bt = Some(bt),
                BtStatus::Success => {
                    // Plan done — clear. Next tick replans.
                    ai.current_bt = None;
                }
                BtStatus::Failure => {
                    ai.current_bt = None;
                    // If the failing plan was a contract run, release
                    // the contract back to the board so another ship
                    // can pick it up (and we can re-plan freely). The
                    // guarded `ReleaseContract` apply is a no-op if
                    // we aren't actually the named fulfiller — which
                    // protects against losing-speculative-accept
                    // ships yanking contracts the winning ship is
                    // still working.
                    if let Some(cid) = economy.active_contract_id.take() {
                        commands.push(SimCommand::ReleaseContract {
                            ship_id: ship_id.clone(),
                            contract_id: cid,
                            reason: "bt_failure",
                        });
                    }
                }
            }
        }

        lifecycle.dirty = true;
    }
}

/// Bundle 2.1: tier weights for the unified utility scorer. Each
/// candidate goal's raw signal is multiplied by the matching tier
/// weight, so biological needs (rest, refuel) dominate when urgency
/// is high, housekeeping (sell_cargo, retrofit) beats strategic
/// when present, and strategic goals (contracts, trades, explore)
/// compete among themselves on their natural log-profit scale. The
/// waterfall is *emergent* rather than hardcoded — a 1% fuel reading
/// produces a score so high no trade can out-bid it, but a 40% fuel
/// reading leaves room for contracts to win if they're profitable.
pub const TIER_BIO_WEIGHT: f32 = 100.0;
pub const TIER_HOUSEKEEPING_WEIGHT: f32 = 40.0;
pub const TIER_STRATEGIC_WEIGHT: f32 = 3.0;
pub const TIER_EXPLORE_WEIGHT: f32 = 6.0;
pub const TIER_IDLE_FLOOR: f32 = 0.5;

/// Onset threshold for the refuel urgency curve. Below this the ship
/// increasingly prioritises refuel; above it, the refuel score goes
/// to 0 (no candidate). Set higher than the former `FUEL_CRITICAL_FRACTION`
/// so the scorer sees the pressure building earlier but only actually
/// dominates when fuel is genuinely low.
pub const FUEL_URGENCY_ONSET: f32 = 0.45;

/// Produced by the per-tick planner for each goal a ship could pursue
/// this tick. The max-scored candidate wins. `score` ≥ 0; 0 means
/// "don't pick this candidate".
#[derive(Debug, Clone)]
pub struct ScoredGoal {
    pub name: &'static str,
    pub score: f32,
    pub bt: BtNode<ShipAction>,
}

/// Bundle 2.2: minimum-commit dwell before a ship may re-plan mid-
/// action. Prevents thrashing when two goals have near-equal scores
/// and the scorer narrowly flips one way then the other.
pub const REPLAN_MIN_COMMIT_TICKS: u64 = 40;

/// Bundle 2.2: cadence for the mid-action replan check. At 8 tps
/// this fires every ~5 seconds of wall-clock — often enough to
/// catch a fresh opportunity, rare enough to keep overhead low
/// (a replan check rebuilds candidate BTs, which isn't free).
///
/// Perf tune 2026-04: bumped from 20 → 40 to halve the number
/// of replan-check ticks. Combined with the per-ship stagger
/// below (a hash-derived offset makes ship A check at tick 40,
/// ship B at tick 41, etc.), the plan_goal work per tick is
/// both halved AND smoothed — no more cliff at every
/// multiple-of-20 tick where every eligible ship plans at once.
pub const REPLAN_CHECK_INTERVAL_TICKS: u64 = 40;

/// Bundle 2.2: how much better the best alternative needs to be
/// before we interrupt the current plan. 1.30 = +30% — enough to
/// tell signal from noise in the personality-weighted score.
pub const REPLAN_SCORE_RATIO: f32 = 1.30;

/// Added to `REPLAN_SCORE_RATIO` when the ship is holding an active
/// contract, on top of the loyalty axis below. Represents the
/// economic weight of the breach itself — rep damage + lost future
/// visibility — that the scorer would otherwise ignore. Empirically
/// motivated: diagnostic showed 91% of breaches were planner-driven
/// replans scoring marginally better than the held contract, even
/// though the breach cost (rep penalty + standing hit) made the
/// switch net-negative. +0.5 raises the floor to 1.80× so the
/// alternative must be nearly 2× better to be worth abandoning.
pub const CONTRACT_OBLIGATION_WEIGHT: f32 = 0.5;

/// Multiplier on `personality.loyalty` (0..=1) added to the
/// in-contract replan ratio. A `reliable_trucker` (loyalty=0.9)
/// gets +0.45 on top of obligation weight — an aggressive_trader
/// (loyalty=0.3) gets +0.15. Makes the loyalty axis load-bearing
/// where it used to be decorative.
pub const LOYALTY_REPLAN_MULTIPLIER: f32 = 0.5;

/// Bundle 2.2: which goals may be interrupted mid-execution.
/// Biological needs (rest_crew, refuel) stay committed — the BT
/// self-terminates on recovery anyway, so interrupting mid-action
/// just loses progress. Housekeeping and retrofit are long-horizon
/// investments the ship shouldn't abandon. Strategic + idle goals
/// are fair game.
pub fn is_replan_eligible(goal: &str) -> bool {
    !matches!(
        goal,
        "rest_crew"
            | "refuel"
            | "seek_retrofit"
            | "sell_cargo"
            | "fulfill_delivery_with_retrofit"
            | "trade_run_with_retrofit"
    )
}

/// Planner: pick a goal + build its BT.
///
/// Bundle 2.1 (A): unified utility scoring. Instead of a hardcoded
/// priority cascade, every candidate goal is scored this tick and
/// the highest-scoring one wins. Scale is set by tier weights above
/// so biological needs at high urgency beat anything strategic, but
/// at modest urgency contracts can compete. Ties and edge cases
/// resolve deterministically by candidate order.
///
/// The goal set is:
/// - **rest_crew** — when morale below CREW_REST_TRIGGER
/// - **refuel** — when fuel below FUEL_URGENCY_ONSET
/// - **sell_cargo** — when cargo onboard
/// - **seek_retrofit** — when caller produced a RetrofitPlan
/// - **fulfill_delivery / contract / passenger / courier / crew_mission** —
///   from `try_plan_contract`, log-profit scored with `prefer_goals` bonus
/// - **trade_run** — from `try_plan_trade_run`, same scoring
/// - **explore / idle_seek_station / idle** — from `smart_idle_fallback`
#[allow(clippy::too_many_arguments)]
#[allow(clippy::too_many_arguments)]
fn plan_goal(
    position: &ShipPosition,
    cargo: &ShipCargo,
    fuel: &ShipFuel,
    economy: &ShipEconomy,
    memory: &ShipMemory,
    crew: Option<&ShipCrew>,
    contracts: &crate::economy::contracts::ContractBoard,
    effective_reputation: &StdHashMap<String, u8>,
    ship_id: &str,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    retrofit: Option<&RetrofitPlan>,
    sensor_range_au: f32,
    location_to_system: &StdHashMap<String, String>,
    personality: &crate::ai::personality::Personality,
    dock_congestion: &StdHashMap<String, (u32, u32, u32)>,
    idle_ticks: u32,
    current_tick: u64,
) -> ScoredGoal {
    let at_loc = match &position.location_name {
        Some(l) => l.clone(),
        None => {
            return ScoredGoal {
                name: "idle",
                score: TIER_IDLE_FLOOR,
                bt: BtNode::action(ShipAction::Idle),
            };
        }
    };

    let mut candidates: Vec<ScoredGoal> = Vec::new();
    // Compute the ship's fuel bucket once — passed into every
    // planner BT builder so synthesised plans reason about real
    // fuel state rather than a full-tank assumption.
    let fuel_bucket = crate::ai::planner::fuel_fraction_to_bucket(fuel.fraction());

    // --- Biological tier: rest + refuel ---
    // Urgency is in [0, 1], steepest near 1.0 so a near-crisis
    // reading blows past housekeeping scores. Personality's
    // morale / safety axes scale how strongly a ship reacts.
    if let Some(c) = crew {
        if c.morale < CREW_REST_TRIGGER
            && any_rest_destination_viable(&at_loc, dock_congestion, location_to_system)
        {
            let urgency = (1.0 - c.morale / CREW_REST_TRIGGER).clamp(0.0, 1.0);
            let score = urgency * personality.morale.max(0.2) * TIER_BIO_WEIGHT;
            // Phase 18L: congestion-aware rest target lookup.
            let target = pick_rest_destination(&at_loc, dock_congestion, location_to_system);
            candidates.push(ScoredGoal {
                name: "rest_crew",
                score,
                bt: build_rest_crew_bt_to(&at_loc, &target, fuel_bucket, registry, gate_pairs),
            });
        }
        // When no viable rest target exists (every same-system station
        // at saturation), skip generating the candidate — the ship
        // will pick another goal (trade_run, fulfill_delivery, explore,
        // idle) and keep moving instead of looping through
        // Dock-timeout-replan at a permanently-full station.
    }
    if fuel.fraction() < FUEL_URGENCY_ONSET {
        let urgency = (1.0 - fuel.fraction() / FUEL_URGENCY_ONSET).clamp(0.0, 1.0);
        let score = urgency * personality.safety.max(0.2) * TIER_BIO_WEIGHT;
        candidates.push(ScoredGoal {
            name: "refuel",
            score,
            bt: build_refuel_bt(),
        });
    }

    // --- Housekeeping tier: sell_cargo + retrofit ---
    // Strong enough to beat strategic when present (ships unload
    // before chasing new contracts), weak enough that a biological
    // crisis still wins. Cargo-fraction scaling means a ship with
    // only a trickle of cargo can still opt to chase a hot
    // contract instead of selling early.
    if cargo.used() > 0 {
        let frac = cargo.used() as f32 / cargo.capacity.max(1) as f32;
        // Scale starts at ~0.5 even for tiny cargo so a bit of
        // cargo is still a reason to unload; asymptotes to 1.0 as
        // the hold fills.
        let scaled = 0.5 + frac.clamp(0.0, 1.0) * 0.5;
        candidates.push(ScoredGoal {
            name: "sell_cargo",
            score: scaled * personality.profit.max(0.3) * TIER_HOUSEKEEPING_WEIGHT,
            bt: build_sell_cargo_bt(),
        });
    }
    // 4. Retrofit opportunity (Phase 18d). The caller already checked
    //    retrofit_points > 0 + credits + stock + fitting-tier.
    if let Some(plan) = retrofit {
        // Retrofit is a long-horizon investment: score moderately
        // so it only fires when nothing more urgent exists. The
        // ship's profit axis reflects "I want to grow my business."
        let score = 0.9 * personality.profit.max(0.3) * TIER_HOUSEKEEPING_WEIGHT;
        candidates.push(ScoredGoal {
            name: "seek_retrofit",
            score,
            bt: build_retrofit_bt(&at_loc, plan, fuel_bucket, registry, gate_pairs),
        });
    }

    // --- Strategic tier: contracts + trade_run ---
    // Log-scaled profit × (1 + prefer_goals bonus) × strategic
    // weight. Archetype `prefer_goals` entries tilt the pick so
    // the fleet fans out instead of every ship running the same
    // waterfall.
    if let Some(c) = try_plan_contract(
        &at_loc,
        cargo,
        economy,
        effective_reputation,
        memory,
        contracts,
        ship_id,
        registry,
        gate_pairs,
        sensor_range_au,
        fuel_bucket,
        location_to_system,
        dock_congestion,
    ) {
        let score = score_strategic(c.profit, c.goal_name, personality);
        // GOAP combined goal: if we have a retrofit plan AND the
        // contract is delivery-class, try to synthesise a single
        // BT that picks up cargo, detours through the shipyard,
        // delivers. When the planner succeeds, register the
        // combined candidate with a small bonus — the ship
        // accomplishes two goals in one trip. Fall through to the
        // plain contract + separate seek_retrofit candidates when
        // the planner bails, so nothing is worse than before.
        if let (Some(rp), Some(dp)) = (retrofit, c.delivery_params.as_ref()) {
            if let Some(combo_bt) = try_build_fulfill_delivery_with_retrofit_planned(
                &at_loc,
                &dp.source,
                &dp.destination,
                dp.commodity,
                dp.quantity,
                &dp.contract_id,
                rp,
                fuel_bucket,
                registry,
                gate_pairs,
            ) {
                // Bonus is small (~20%) — we want combined plans
                // to win when roughly on par, not dominate when
                // delivery alone is clearly better.
                let combo_score = score * 1.20
                    + score_strategic(rp.cost / 5, "seek_retrofit", personality);
                candidates.push(ScoredGoal {
                    name: "fulfill_delivery_with_retrofit",
                    score: combo_score,
                    bt: combo_bt,
                });
            }
        }
        candidates.push(ScoredGoal {
            name: c.goal_name,
            score,
            bt: c.bt,
        });
    }
    if let Some(t) = try_plan_trade_run(&at_loc, memory, registry, gate_pairs, current_tick, fuel_bucket) {
        let score = score_strategic(t.profit, "trade_run", personality);
        // GOAP combined goal: trade_run + retrofit. Same pattern as
        // delivery + retrofit. When the planner folds refit into
        // the trade-run path it wins on two fronts in one trip.
        if let Some(rp) = retrofit {
            if let Some(combo_bt) = try_build_trade_run_with_retrofit_planned(
                &at_loc,
                &t.buy_loc,
                &t.sell_loc,
                t.commodity,
                rp,
                fuel_bucket,
                registry,
                gate_pairs,
            ) {
                let combo_score = score * 1.20
                    + score_strategic(rp.cost / 5, "seek_retrofit", personality);
                candidates.push(ScoredGoal {
                    name: "trade_run_with_retrofit",
                    score: combo_score,
                    bt: combo_bt,
                });
            }
        }
        candidates.push(ScoredGoal {
            name: "trade_run",
            score,
            bt: t.bt,
        });
    }

    // --- Exploration / idle fallback tier ---
    // smart_idle_fallback's ladder (explore → idle_seek_station →
    // plain idle) is always at least a low-score baseline so
    // something is always pickable. Exploration scores a bit
    // higher when the ship's personality actually wants it.
    let (idle_name, idle_bt) = smart_idle_fallback(
        &at_loc,
        position,
        economy,
        fuel,
        memory,
        registry,
        gate_pairs,
        location_to_system,
        personality,
        idle_ticks,
    );
    let idle_score = match idle_name {
        "explore" => personality.exploration.max(0.2) * TIER_EXPLORE_WEIGHT,
        "idle_seek_station" => 0.8 * TIER_EXPLORE_WEIGHT,
        _ => TIER_IDLE_FLOOR,
    };
    if let Some(bt) = idle_bt {
        candidates.push(ScoredGoal {
            name: idle_name,
            score: idle_score,
            bt,
        });
    } else {
        // Shouldn't happen (smart_idle_fallback always returns a BT)
        // but keep a belt-and-braces fallback so we always return
        // something pickable.
        candidates.push(ScoredGoal {
            name: "idle",
            score: TIER_IDLE_FLOOR,
            bt: BtNode::action(ShipAction::Idle),
        });
    }

    // Pick max-score candidate. Ties resolve by earliest-pushed
    // (biological / housekeeping / strategic / idle order above),
    // which matches the Phase-18i waterfall's tie-breaks.
    candidates
        .into_iter()
        .max_by(|a, b| a.score.partial_cmp(&b.score).unwrap_or(std::cmp::Ordering::Equal))
        .expect("idle fallback guarantees at least one candidate")
}

/// Bundle 2.1: shared scoring for the strategic tier (contracts,
/// trade_run). Log-scales profit so a 100k-credit subsidy doesn't
/// automatically swamp a 1.5k courier run, multiplies by
/// `1.0 + prefer_goals[goal]` so archetype bonuses tilt the pick,
/// then by the ship's profit axis and the tier weight.
pub(super) fn score_strategic(
    profit: i64,
    goal_name: &str,
    personality: &crate::ai::personality::Personality,
) -> f32 {
    if profit <= 0 {
        return 0.0;
    }
    let log_profit = (profit as f32).max(1.0).ln();
    let bonus = personality
        .prefer_goals
        .get(goal_name)
        .copied()
        .unwrap_or(0.0);
    log_profit * (1.0 + bonus) * personality.profit.max(0.3) * TIER_STRATEGIC_WEIGHT
}

/// Phase 19h: smart idle branch. When the contract / trade_run
/// planners both struck out, we pick from a ladder:
///
///   1. **Ship has been idling at a station a while + fuel + credits
///      OK + personality leans adventurous**: pick a neighbour system
///      not in `recent_systems`, build an explore BT that travels to
///      the outbound gate, jumps, travels to a station in the new
///      system, docks, dwells ~5s to catch a posting cycle, undocks.
///      Goal = `"explore"`.
///   2. **At a location without any dockable facility** (weird spawn
///      or gate-only locations): travel to the nearest same-system
///      dockable station. Goal = `"idle_seek_station"`. Gives the
///      ship a chance to observe prices + refuel while resting.
///   3. **Otherwise**: plain Idle — the ship stays where it is. Some
///      captains just want quiet.
#[allow(clippy::too_many_arguments)]
fn smart_idle_fallback(
    at_loc: &str,
    position: &ShipPosition,
    economy: &ShipEconomy,
    fuel: &ShipFuel,
    memory: &ShipMemory,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    location_to_system: &StdHashMap<String, String>,
    personality: &crate::ai::personality::Personality,
    idle_ticks: u32,
) -> (&'static str, Option<BtNode<ShipAction>>) {
    let fuel_ok = fuel.fraction() >= EXPLORE_MIN_FUEL_FRACTION;
    let credits_ok = economy.credits >= EXPLORE_MIN_CREDITS;

    // Personality tilts the idle-duration trigger. High `exploration`
    // → leaves sooner; high `safety` → lingers longer; low credits
    // also bias toward desperation.
    let explore_bonus = personality.exploration - personality.safety * 0.5;
    let desperation = if economy.credits < 5000 { 0.3 } else { 0.0 };
    let trigger_scale = (1.0 - explore_bonus - desperation).max(0.25);
    let effective_trigger = (IDLE_EXPLORE_TICKS as f32 * trigger_scale) as u32;

    let should_explore = idle_ticks >= effective_trigger && fuel_ok && credits_ok;

    if should_explore {
        if let Some(bt) =
            try_build_explore_bt(at_loc, memory, registry, gate_pairs, location_to_system)
        {
            return ("explore", Some(bt));
        }
    }

    // Dock-less location? Travel to a same-system station.
    if position.docked_at.is_none() && !has_dockable_here(at_loc, registry) {
        if let Some(station) = pick_same_system_station(at_loc, registry, location_to_system) {
            let mut steps: Vec<BtNode<ShipAction>> = Vec::new();
            for a in route_actions(at_loc, &station, registry, gate_pairs) {
                steps.push(BtNode::action(a));
            }
            steps.push(BtNode::action(ShipAction::Dock));
            steps.push(BtNode::action(ShipAction::DockDwell {
                seconds: EXPLORE_CHECK_BOARD_SECONDS,
            }));
            steps.push(BtNode::action(ShipAction::Undock));
            return ("idle_seek_station", Some(BtNode::sequence(steps)));
        }
    }

    // Default: stay put.
    ("idle", Some(BtNode::action(ShipAction::Idle)))
}

/// Pick an adjacent star system not in `memory.recent_systems` and
/// build the explore BT to reach it. Returns `None` when the ship has
/// no outbound gate or every neighbor is already in the recent-visits
/// set (the rare deep-exploration case — we'll re-plan next cycle).
fn try_build_explore_bt(
    at_loc: &str,
    memory: &ShipMemory,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    location_to_system: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    let current_system = location_to_system.get(at_loc)?;

    // Walk this system's gates, find ones whose paired gate lands in
    // a system not currently in the ship's recent-systems window.
    // Fall back to any neighbour if every candidate is on the list
    // (prevents total stall when memory has cycled through the
    // whole connected graph).
    let mut preferred: Vec<(String, String, String)> = Vec::new();
    let mut any: Vec<(String, String, String)> = Vec::new();
    for (src_gate, dst_gate) in gate_pairs {
        let Some(src_sys) = location_to_system.get(src_gate) else {
            continue;
        };
        if src_sys != current_system {
            continue;
        }
        let Some(dst_sys) = location_to_system.get(dst_gate) else {
            continue;
        };
        let entry = (src_gate.clone(), dst_gate.clone(), dst_sys.clone());
        if !memory.recent_systems.iter().any(|s| s == dst_sys) {
            preferred.push(entry.clone());
        }
        any.push(entry);
    }
    let (src_gate, dst_gate, dst_system) = if let Some(p) = preferred.first() {
        p.clone()
    } else {
        any.first()?.clone()
    };

    // Landing target: a dockable station in the destination system
    // (not the gate itself — gates aren't where contracts are). Pick
    // the first station we find; `pick_same_system_station` handles
    // the has-dockable check for us.
    let landing_station = pick_same_system_station(&dst_gate, registry, location_to_system)
        .unwrap_or_else(|| dst_gate.clone());

    let mut steps: Vec<BtNode<ShipAction>> = Vec::new();
    // Travel to the outbound gate.
    for a in route_actions(at_loc, &src_gate, registry, gate_pairs) {
        steps.push(BtNode::action(a));
    }
    // Gate jump.
    steps.push(BtNode::action(ShipAction::GateJump {
        src_gate,
        dest_gate: dst_gate.clone(),
    }));
    // Travel to the landing station + dwell "check the board".
    for a in route_actions(&dst_gate, &landing_station, registry, gate_pairs) {
        steps.push(BtNode::action(a));
    }
    steps.push(BtNode::action(ShipAction::Dock));
    steps.push(BtNode::action(ShipAction::DockDwell {
        seconds: EXPLORE_CHECK_BOARD_SECONDS,
    }));
    steps.push(BtNode::action(ShipAction::Undock));

    let _ = dst_system; // silence warnings if we later use it for events
    Some(BtNode::sequence(steps))
}

/// Is there a dockable (non-gate, capacity > 0) facility at this
/// location? Used by the idle-at-station logic to decide whether the
/// ship should wander to a real port.
fn has_dockable_here(at_loc: &str, registry: &WorldRegistry) -> bool {
    registry
        .locations
        .contains_key(at_loc)
}

/// Pick any non-gate station in the same star system as `at_loc`.
/// First-match rather than optimised — idle-seeking doesn't need the
/// best pick, just a pick. Skips the caller's current location so
/// the ship actually goes somewhere.
fn pick_same_system_station(
    at_loc: &str,
    registry: &WorldRegistry,
    location_to_system: &StdHashMap<String, String>,
) -> Option<String> {
    let current_system = location_to_system.get(at_loc)?;
    for (name, _info) in registry.locations.iter() {
        if name == at_loc {
            continue;
        }
        if name.contains("gate") {
            // Gates are technically locations but they don't host
            // contracts or markets — bad "chill here" targets.
            continue;
        }
        if let Some(sys) = location_to_system.get(name) {
            if sys == current_system {
                return Some(name.clone());
            }
        }
    }
    None
}

/// Try to find a profitable fulfill plan from the board. Handles both
/// delivery contracts (ship must pre-buy the commodity at source, must
/// profit after cost) and passenger / courier contracts (no buy step —
/// the ship just shuttles between source and destination).
/// Result of a successful contract plan: the personality-facing goal
/// name (matches archetype `prefer_goals` keys), the profit the planner
/// thinks the ship can collect after cost, and the BT to execute.
/// Phase 18i: returned instead of just a BT so `plan_goal` can score it
/// against competing goals (trade_run) via the ship's personality.
pub struct ContractCandidate {
    pub goal_name: &'static str,
    pub profit: i64,
    pub bt: BtNode<ShipAction>,
    /// Raw delivery params when the contract is a delivery-class
    /// kind (Delivery / Subsidy / Construction). Used by `plan_goal`
    /// to re-synthesise a combined delivery+retrofit BT when both
    /// opportunities align. `None` for Passenger / Courier /
    /// CrewMission / other non-delivery variants.
    pub delivery_params: Option<DeliveryParams>,
}

/// Raw delivery parameters for combined-goal BT synthesis. Mirrors
/// the args `build_fulfill_delivery_bt` takes so a caller can build
/// an alternate BT (retrofit-on-route, e.g.) without threading the
/// entire contract board through.
#[derive(Debug, Clone)]
pub struct DeliveryParams {
    pub source: String,
    pub destination: String,
    pub commodity: Commodity,
    pub quantity: u32,
    pub contract_id: String,
}

#[allow(clippy::too_many_arguments)]
fn try_plan_contract(
    at_loc: &str,
    cargo: &ShipCargo,
    economy: &ShipEconomy,
    effective_reputation: &StdHashMap<String, u8>,
    memory: &ShipMemory,
    contracts: &crate::economy::contracts::ContractBoard,
    _ship_id: &str,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    sensor_range_au: f32,
    fuel_bucket: u8,
    location_to_system: &StdHashMap<String, String>,
    dock_congestion: &StdHashMap<String, (u32, u32, u32)>,
) -> Option<ContractCandidate> {
    use crate::economy::contracts::ContractType;

    // Phase 18f: cross-system contracts are invisible to ships with
    // short-range sensors. A contract counts as cross-system when its
    // source + destination resolve to different star systems; ships
    // below the threshold skip those, simulating "the comms relay
    // just isn't picking up interstellar job boards." Larger hulls
    // (size ≥ 5) ship with tier-2 sensors by default and see them
    // day one; small ships need a sensor retrofit.
    let ship_system = location_to_system.get(at_loc);

    #[derive(Clone)]
    struct Candidate {
        id: String,
        source: String,
        destination: String,
        commodity: Commodity,
        qty: u32,
        payment: i64,
        cost: i64,
        /// Phase 19f: effective profit used for comparison — raw
        /// profit adjusted by a fill-ratio quality multiplier for
        /// delivery kinds. The `profit` passed to the planner's
        /// `score_goal` scoring still uses raw profit, so the
        /// cross-goal (trade_run vs delivery) comparison stays
        /// consistent with the old rules.
        score: i64,
        kind: ContractType,
    }
    let mut best: Option<Candidate> = None;

    for c in contracts.posted_for_ship(effective_reputation) {
        // Phase 18f: sensor-range gate for cross-system contracts.
        // If the contract's source and destination span different
        // systems (or leave the ship's system) and the ship's
        // sensor range is below the cross-system threshold, skip.
        if sensor_range_au < CROSS_SYSTEM_SENSOR_RANGE_AU {
            let src_sys = location_to_system.get(&c.source_location);
            let dst_sys = location_to_system.get(&c.destination_location);
            let is_cross_system = match (ship_system, src_sys, dst_sys) {
                (Some(ship), Some(src), Some(dst)) => ship != src || src != dst,
                // Missing system data for any of the three means we
                // can't prove same-system — fall back to "visible"
                // rather than blocking everything during startup.
                _ => false,
            };
            if is_cross_system {
                continue;
            }
        }
        // 2026-04-24: pre-accept congestion gate. A 20-minute soak
        // revealed 50+ ships piling on a single 10-cap farm because
        // the scorer only evaluated contract *profit*, not whether
        // the ship could actually complete the delivery in finite
        // time. Don't accept a contract whose source OR destination
        // is already choked to 3× capacity — let another ship take
        // it once the queue drains, or let the faction post a
        // construction contract for a second facility. Skips when
        // the location isn't in `dock_congestion` (e.g. gate-only
        // locations, startup race).
        if contract_destination_is_saturated(&c.source_location, dock_congestion)
            || contract_destination_is_saturated(&c.destination_location, dock_congestion)
        {
            continue;
        }
        // Passenger / courier / crew-mission contracts don't occupy cargo
        // slots — treat them as "hop-around" jobs in the planner.
        let is_passenger = c.contract_type == ContractType::Passenger;
        let is_courier = c.contract_type == ContractType::Courier;
        let is_mission = c.contract_type == ContractType::CrewMission;
        if !is_passenger && !is_mission && c.quantity > cargo.capacity {
            continue;
        }

        let buy_cost: i64 = if is_passenger || is_courier || is_mission {
            // No pre-buy for these kinds. Passenger pickup is implicit;
            // courier's cargo is supplied by the poster; crew missions
            // have no cargo at all — the ship just dwells at the posting
            // station for the mission's duration_ticks and collects pay.
            0
        } else {
            // Prefer the ship's direct memory of the source market.
            // Phase 19h: when memory is missing (comms-tier-limited
            // ships rarely know far-flung markets), fall back to a
            // median across the ship's OTHER remembered markets for
            // this commodity — a heuristic "prices are probably
            // similar" guess. That lets tier-1 comms ships
            // speculatively price cross-system contracts instead of
            // skipping every one. Buy cost is still validated on
            // arrival at the source market, so a bad guess just
            // means the BT might bail on Buy (Failure → release
            // contract). No new state threading required.
            let src_price_known = memory
                .price_knowledge
                .get(&c.source_location)
                .and_then(|m| m.get(&c.commodity))
                .map(|p| p.price);
            let src_price = src_price_known
                .or_else(|| median_known_price(memory, c.commodity));
            match src_price {
                Some(p) => (p * c.quantity as f32) as i64,
                // No memory of this commodity at ANY market → can't
                // even guess. Skip as before.
                None => continue,
            }
        };
        // Rough upper-bound estimate of gate fees along the full route
        // (current → source → destination). Uses default fees; real
        // fees are whatever the gate facility carries. We don't know
        // cargo-at-pickup yet, so approximate with contract quantity.
        let gate_fees = estimate_route_gate_fees(
            &[
                (at_loc, &c.source_location),
                (&c.source_location, &c.destination_location),
            ],
            gate_pairs,
            c.quantity,
        );
        let cost: i64 = buy_cost + gate_fees;
        if cost >= c.payment {
            continue;
        }
        if economy.credits < cost {
            continue;
        }
        let profit = c.payment - cost;

        // Phase 19f: fill-ratio scoring. For delivery contracts, reward
        // runs that make good use of the ship's cargo capacity. A
        // hauler with capacity 2000 picking up a 50-unit delivery
        // wastes 97.5% of the hold — sqrt(0.025) ≈ 0.16, so that
        // delivery scores only ~16% of its raw profit in the planner
        // comparison. Applied only to kinds that actually load cargo.
        let fill_quality: f32 = if matches!(
            c.contract_type,
            ContractType::Delivery | ContractType::Construction
        ) && cargo.capacity > 0
        {
            let ratio = (c.quantity as f32 / cargo.capacity as f32).clamp(0.0, 1.0);
            // sqrt curve: gentle at the top (90% fill → 0.95), steep
            // at the bottom (5% fill → 0.22). Small contracts on big
            // hulls are still takeable, just unattractive compared
            // to better-fitting alternatives.
            ratio.sqrt().max(0.1)
        } else {
            1.0
        };
        let effective_profit: i64 = ((profit as f32) * fill_quality).round() as i64;

        let better = best
            .as_ref()
            .is_none_or(|b| effective_profit > b.score);
        if better {
            best = Some(Candidate {
                id: c.id.clone(),
                source: c.source_location.clone(),
                destination: c.destination_location.clone(),
                commodity: c.commodity,
                qty: c.quantity,
                payment: c.payment,
                cost,
                score: effective_profit,
                kind: c.contract_type,
            });
        }
    }
    let cand = best?;
    let profit = cand.payment - cand.cost;

    // Snapshot delivery params before `cand.id` gets moved into the
    // BT builder below — we need them for the `delivery_params`
    // field on `ContractCandidate` so downstream callers can
    // re-synthesise a combined delivery+retrofit BT.
    let delivery_params = match cand.kind {
        ContractType::Delivery | ContractType::Subsidy | ContractType::Construction => {
            Some(DeliveryParams {
                source: cand.source.clone(),
                destination: cand.destination.clone(),
                commodity: cand.commodity,
                quantity: cand.qty,
                contract_id: cand.id.clone(),
            })
        }
        _ => None,
    };

    // Kind-specific goal name — matches the personality archetype
    // `prefer_goals` keys (e.g. `courier` archetype weights
    // `fulfill_passenger_transport`, `reliable_trucker` weights
    // `fulfill_delivery`, etc). Phase 18i.
    let (goal_name, bt) = match cand.kind {
        ContractType::CrewMission => (
            "do_crew_mission",
            build_fulfill_crew_mission_bt(
                at_loc,
                &cand.source,
                cand.id,
                fuel_bucket,
                registry,
                gate_pairs,
            ),
        ),
        ContractType::Passenger => (
            "fulfill_passenger_transport",
            build_fulfill_passenger_bt(
                at_loc,
                &cand.source,
                &cand.destination,
                cand.id,
                fuel_bucket,
                registry,
                gate_pairs,
            ),
        ),
        ContractType::Courier => (
            "fulfill_courier",
            build_fulfill_passenger_bt(
                at_loc,
                &cand.source,
                &cand.destination,
                cand.id,
                fuel_bucket,
                registry,
                gate_pairs,
            ),
        ),
        ContractType::Subsidy => (
            "fulfill_contract",
            build_fulfill_delivery_bt(
                at_loc,
                &cand.source,
                &cand.destination,
                cand.commodity,
                cand.qty,
                cand.id,
                fuel_bucket,
                registry,
                gate_pairs,
            ),
        ),
        ContractType::Construction => (
            "fulfill_construction",
            build_fulfill_delivery_bt(
                at_loc,
                &cand.source,
                &cand.destination,
                cand.commodity,
                cand.qty,
                cand.id,
                fuel_bucket,
                registry,
                gate_pairs,
            ),
        ),
        _ => (
            "fulfill_delivery",
            build_fulfill_delivery_bt(
                at_loc,
                &cand.source,
                &cand.destination,
                cand.commodity,
                cand.qty,
                cand.id,
                fuel_bucket,
                registry,
                gate_pairs,
            ),
        ),
    };
    Some(ContractCandidate {
        goal_name,
        profit,
        bt,
        delivery_params,
    })
}

/// Build a crew-mission BT. Travel to the station, dock, refuel, rest
/// (the dwell — Rest returns Running until morale >= target, which
/// approximates the mission's duration_ticks). Then Deliver claims the
/// payout; Undock.
#[allow(clippy::too_many_arguments)]
fn build_fulfill_crew_mission_bt(
    current: &str,
    station: &str,
    contract_id: String,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    // Hand-authored fallback retired — the planner owns this goal.
    // If the planner somehow fails (bug, depth cap exceeded), the
    // ship returns an Idle BT for one tick and replans next tick
    // with whatever state has changed. See the GOAP arc commits.
    try_build_fulfill_crew_mission_bt_planned(
        current,
        station,
        &contract_id,
        fuel_bucket,
        registry,
        gate_pairs,
    )
    .unwrap_or_else(|| BtNode::action(ShipAction::Idle))
}

/// GOAP: crew-mission planner. Single-station mission (travel →
/// dock → refuel → rest → deliver payout → undock). Ordering is
/// enforced by the Rest precondition and the
/// `delivered && rested` goal predicate.
fn try_build_fulfill_crew_mission_bt_planned(
    current: &str,
    station: &str,
    contract_id: &str,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };
    let map = LocMap::delivery(
        current.to_string(),
        current.to_string(), // Source placeholder (unused by crew_mission_catalog)
        station.to_string(),
        Commodity::Food,
        0,
        contract_id.to_string(),
        0,
        0,
        cost(current, station),
    );
    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.delivered && s.rested && s.fuel_bucket >= 2,
        Operator::crew_mission_catalog(),
        &map,
        20,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

/// Build a passenger/courier BT. No Buy step; the ship just hops between
/// source and destination and collects payment on Deliver.
#[allow(clippy::too_many_arguments)]
fn build_fulfill_passenger_bt(
    current: &str,
    source: &str,
    destination: &str,
    contract_id: String,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    try_build_fulfill_passenger_bt_planned(
        current,
        source,
        destination,
        &contract_id,
        fuel_bucket,
        registry,
        gate_pairs,
    )
    .unwrap_or_else(|| BtNode::action(ShipAction::Idle))
}

/// GOAP: forward planner for passenger / courier contracts. No
/// cargo mechanics — goal is `delivered && fuel_bucket >= 2`, and
/// the `passenger_catalog` has no Buy / SellAll / Refit operators
/// so plans are naturally compact (just dock at source, undock,
/// travel, dock at dest, deliver).
fn try_build_fulfill_passenger_bt_planned(
    current: &str,
    source: &str,
    destination: &str,
    contract_id: &str,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };
    // Passenger contracts ignore commodity + quantity; pass a
    // sentinel to satisfy LocMap's delivery constructor.
    let map = LocMap::delivery(
        current.to_string(),
        source.to_string(),
        destination.to_string(),
        Commodity::Food,
        0,
        contract_id.to_string(),
        cost(current, source),
        cost(source, destination),
        cost(current, destination),
    );
    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.delivered && s.fuel_bucket >= 2,
        Operator::passenger_catalog(),
        &map,
        16,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

// --- BT builders ---

/// Wall-clock dwell (seconds) injected after Dock and before Undock so
/// the ship visibly sits at the pad doing "station business" — cargo
/// handling, crew embark/disembark, paperwork — instead of the whole
/// dock sequence rattling through in 3 ticks. Kept small so it doesn't
/// cripple the economy; refuel + sell multi-tick actions do most of the
/// real dwell work.
const DOCK_ARRIVE_DWELL_SECS: u8 = 2;
const DOCK_DEPART_DWELL_SECS: u8 = 2;

fn build_refuel_bt() -> BtNode<ShipAction> {
    BtNode::sequence(vec![
        BtNode::action(ShipAction::Dock),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }),
        BtNode::action(ShipAction::Refuel),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }),
        BtNode::action(ShipAction::Undock),
    ])
}

fn build_sell_cargo_bt() -> BtNode<ShipAction> {
    BtNode::sequence(vec![
        BtNode::action(ShipAction::Dock),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }),
        BtNode::action(ShipAction::SellAll),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }),
        BtNode::action(ShipAction::Undock),
    ])
}

#[allow(dead_code)]
fn build_rest_crew_bt() -> BtNode<ShipAction> {
    BtNode::sequence(vec![
        BtNode::action(ShipAction::Dock),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }),
        BtNode::action(ShipAction::Refuel),
        BtNode::action(ShipAction::Rest),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }),
        BtNode::action(ShipAction::Undock),
    ])
}

/// Phase 18L: congestion-aware rest-crew BT. Routes to `target`
/// (which may differ from `current` when the current location is
/// saturated), then dock + refuel + rest + undock. If target ==
/// current, the route leg is empty — identical behavior to the
/// pre-18L flat sequence.
#[allow(clippy::too_many_arguments)]
fn build_rest_crew_bt_to(
    current: &str,
    target: &str,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    try_build_rest_crew_bt_to_planned(current, target, fuel_bucket, registry, gate_pairs)
        .unwrap_or_else(|| BtNode::action(ShipAction::Idle))
}

/// GOAP: rest_crew planner. Goal =
/// `rested && !docked && at == Dest && fuel_bucket >= 2`. The
/// `rest_crew_catalog` has no cargo / contract ops so plans are
/// tightly scoped to travel-dock-rest-undock.
fn try_build_rest_crew_bt_to_planned(
    current: &str,
    target: &str,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };
    let map = LocMap::delivery(
        current.to_string(),
        current.to_string(), // Source placeholder (unused by rest_crew_catalog)
        target.to_string(),
        Commodity::Food,
        0,
        String::new(), // no contract
        0,
        0,
        cost(current, target),
    );
    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.rested && !s.docked && s.at == Loc::Dest && s.fuel_bucket >= 2,
        Operator::rest_crew_catalog(),
        &map,
        16,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

/// Saturation threshold for "effectively full" — effective_load
/// (docked + queued) / capacity >= this → treat as unavailable for
/// new arrivals. 1.2 so a station with a queue equal to 20% of its
/// dock capacity is still considered viable, but the moment the
/// queue grows large enough that new arrivals face a long wait,
/// the planner routes elsewhere. Post-tick-21k-spiral fix: the
/// prior check (docked >= cap) missed queue pressure entirely and
/// 170 ships piled onto one 25-slot station.
pub const DOCK_SATURATION_THRESHOLD: f32 = 1.2;

/// True when a location is effectively saturated: no capacity, OR
/// `(docked + queued) / capacity >= DOCK_SATURATION_THRESHOLD`.
/// Returns `true` for unknown locations so unknown targets are
/// never picked.
fn location_saturated(cap: u32, docked: u32, queued: u32) -> bool {
    if cap == 0 {
        return true;
    }
    let effective_load = docked as f32 + queued as f32;
    effective_load / cap as f32 >= DOCK_SATURATION_THRESHOLD
}

/// Multiplier applied to capacity for the contract-acceptance
/// congestion gate (see `contract_destination_is_saturated`). Much
/// higher than the rest-destination threshold because contracts
/// are longer-committed: a rest decision reverses cheaply, a
/// contract acceptance commits the ship for many ticks. 3× means
/// a 10-cap farm has to be choked past 30 queued before ships
/// stop signing up for deliveries to/from it.
pub const CONTRACT_ACCEPT_QUEUE_MULTIPLIER: f32 = 3.0;

/// Pre-accept congestion gate for contract candidates. True when
/// `location`'s aggregated queue length exceeds
/// `CONTRACT_ACCEPT_QUEUE_MULTIPLIER × capacity`. Missing
/// entries in `dock_congestion` (gate-only locations, startup
/// race) return false — don't block when we can't prove
/// saturation.
fn contract_destination_is_saturated(
    location: &str,
    dock_congestion: &StdHashMap<String, (u32, u32, u32)>,
) -> bool {
    let Some(&(cap, _docked, queued)) = dock_congestion.get(location) else {
        return false;
    };
    if cap == 0 {
        return false;
    }
    queued as f32 >= CONTRACT_ACCEPT_QUEUE_MULTIPLIER * cap as f32
}

/// Phase 18L + post-21k-spiral fix: pick the best rest destination
/// given current location and a per-location congestion snapshot.
/// Prefers the current location if it has free slots (and isn't
/// overly queued); otherwise picks the least-congested station in
/// the same system. Falls back to current if every same-system
/// alternative is also saturated.
///
/// Congestion scored as `(docked + queued) / capacity` — queue
/// pressure counts against a station for routing decisions, so
/// ships don't pile onto an already-queue-bloated dock.
/// Same-system constraint so ships don't pathfind across gates
/// just for shore leave.
pub fn pick_rest_destination(
    current: &str,
    congestion: &StdHashMap<String, (u32, u32, u32)>,
    location_to_system: &StdHashMap<String, String>,
) -> String {
    let current_load = congestion.get(current);
    // Short-circuit: if current has a free dock slot RIGHT NOW,
    // stay here — no fuel cost to travelling.
    if let Some(&(cap, docked, _)) = current_load {
        if cap > 0 && docked < cap {
            return current.to_string();
        }
    }
    // Otherwise, compare current against siblings by effective
    // load (docked + queued) / cap. Skip over-saturated siblings
    // entirely; pick the strictly-less-loaded one; fall back to
    // current when no sibling is a strict improvement.
    let current_sat = current_load
        .map(|&(cap, docked, queued)| {
            (docked as f32 + queued as f32) / cap.max(1) as f32
        })
        .unwrap_or(f32::INFINITY);
    let ship_sys = location_to_system.get(current);
    let mut best: Option<(String, f32)> = None;
    for (loc, &(cap, docked, queued)) in congestion.iter() {
        if location_saturated(cap, docked, queued) {
            continue;
        }
        let loc_sys = location_to_system.get(loc);
        if ship_sys.is_some() && ship_sys != loc_sys {
            continue;
        }
        let saturation = (docked as f32 + queued as f32) / cap as f32;
        if best.as_ref().is_none_or(|(_, s)| saturation < *s) {
            best = Some((loc.clone(), saturation));
        }
    }
    // Route to sibling only if it's strictly less loaded than
    // current — ties go to current (stay, skip the fuel cost).
    match best {
        Some((loc, sat)) if sat < current_sat => loc,
        _ => current.to_string(),
    }
}

/// Fix 2: rest-crew viability check. Returns true when at least one
/// same-system station has free effective capacity. Called before
/// `plan_goal` generates a `rest_crew` candidate — if no viable
/// target exists anywhere in the ship's system, the ship lets
/// other goals compete rather than queue-forever at a saturated
/// station. Without this, 170 ships all picked `rest_crew` at
/// forge-smelter (25 slots) and pinned the fleet into a
/// replan-queue-timeout death spiral.
pub(super) fn any_rest_destination_viable(
    current: &str,
    congestion: &StdHashMap<String, (u32, u32, u32)>,
    location_to_system: &StdHashMap<String, String>,
) -> bool {
    // Current location viable? Short-circuit.
    if let Some(&(cap, docked, queued)) = congestion.get(current) {
        if !location_saturated(cap, docked, queued) {
            return true;
        }
    }
    // Any other same-system station viable?
    let ship_sys = location_to_system.get(current);
    congestion.iter().any(|(loc, &(cap, docked, queued))| {
        if location_saturated(cap, docked, queued) {
            return false;
        }
        let loc_sys = location_to_system.get(loc);
        ship_sys.is_some() && ship_sys == loc_sys
    })
}

/// Build a trade_run BT. Start at `current`, visit `buy_loc`, buy `commodity`,
/// travel to `sell_loc`, sell, end at sell_loc.
///
/// If `current == buy_loc`, skip the initial travel leg.
/// Proposed retrofit the planner has already costed and located. Built
/// by [`find_retrofit_opportunity`] from a ship's fitting + a per-tick
/// snapshot of shipyard inventories. The planner turns this into a
/// `build_retrofit_bt` goal when the ship qualifies (has points +
/// credits + isn't in a higher-priority state).
#[derive(Debug, Clone)]
pub struct RetrofitPlan {
    pub shipyard_location: String,
    pub slot: crate::modules::Slot,
    pub slug: &'static str,
    pub cost: i64,
}

/// Snapshot of every shipyard's available inventory, built once per
/// `decide_and_act` call so each ship's planner can consult it without
/// re-querying hecs. `Vec` keeps order deterministic run-over-run.
///
/// Each entry is `(location_name, system_id, stock)` — system is
/// derived from the yard's body via `BodyIdentity.system_name` and
/// powers the "same-system first" retrofit preference.
pub type ShipyardInventorySnapshot =
    Vec<(String, String, std::collections::HashMap<String, u32>)>;

/// Credits floor a ship keeps in reserve before considering an
/// autonomous retrofit. Refits are meant to be rare; no ship burns
/// its last coins on a cargo-bay upgrade. Keep well above the
/// cheapest tier-2 module (5500 cr) so the ship still has operating
/// credits after a purchase.
pub const RETROFIT_CREDIT_RESERVE: i64 = 12_000;

/// Given a ship's current fitting and the global shipyard inventory
/// snapshot, pick at most one concrete retrofit target: which slot to
/// upgrade, to which slug, and where. Returns `None` if no eligible
/// swap exists — every slot already at tier 3, or no shipyard carries
/// a matching upgrade in stock.
///
/// Selection policy:
///  - Walk slots in canonical order (engine, cargo, sensors, reactor, comms).
///  - Target `current_tier + 1` (skip if already at 3).
///  - Among yards carrying the target slug, prefer (in order): same
///    location (no travel), same system (no gate hop), any other.
///    Keeps Tau Ceti ships from flying to Earth for a routine refit
///    when their home yard has stock.
pub fn find_retrofit_opportunity(
    fitting: &ShipFitting,
    inventory: &ShipyardInventorySnapshot,
    ship_credits: i64,
    ship_location: &str,
    ship_system: &str,
) -> Option<RetrofitPlan> {
    if ship_credits < RETROFIT_CREDIT_RESERVE {
        return None;
    }
    for slot in crate::modules::SLOTS.iter().copied() {
        // Determine current tier in this slot (1 when empty — nothing
        // to upgrade toward past 3).
        let current_tier = fitting
            .slot_slug(slot)
            .and_then(crate::modules::get)
            .map(|d| d.tier)
            .unwrap_or(1);
        if current_tier >= 3 {
            continue;
        }
        let target_tier = current_tier + 1;
        // Canonical slug for {slot}_t{target_tier} — matches how the
        // catalog names entries. A richer catalog (same slot, multiple
        // same-tier variants) would need a lookup; keep it simple.
        let slug_owned = format!("{}_t{}", slot.as_str(), target_tier);
        let Some(def) = crate::modules::get(&slug_owned) else {
            continue;
        };
        let Some(recipe) = crate::economy::module_production::get(def.slug) else {
            continue;
        };
        // Need to afford the purchase AND stay above reserve afterwards.
        if ship_credits - recipe.base_cost_credits < RETROFIT_CREDIT_RESERVE {
            continue;
        }
        // Rank yards carrying this slug by proximity: same location
        // first, then same system, then anywhere else. `min_by_key`
        // picks the lowest score; ties broken by Vec iteration order
        // (deterministic per run).
        let Some((loc, _, _)) = inventory
            .iter()
            .filter(|(_, _, stock)| stock.get(def.slug).copied().unwrap_or(0) > 0)
            .min_by_key(|(loc, system, _)| {
                if loc == ship_location {
                    0u8
                } else if !ship_system.is_empty() && system == ship_system {
                    1
                } else {
                    2
                }
            })
        else {
            continue;
        };
        return Some(RetrofitPlan {
            shipyard_location: loc.clone(),
            slot,
            slug: def.slug,
            cost: recipe.base_cost_credits,
        });
    }
    None
}

#[allow(clippy::too_many_arguments)]
fn build_retrofit_bt(
    current: &str,
    plan: &RetrofitPlan,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    try_build_retrofit_bt_planned(current, plan, fuel_bucket, registry, gate_pairs)
        .unwrap_or_else(|| BtNode::action(ShipAction::Idle))
}

/// GOAP: forward planner for standalone retrofit. Uses the
/// `retrofit_catalog` which has no cargo operators. Goal =
/// `retrofitted && fuel_bucket >= 2`. Travel is only meaningful
/// to the shipyard, so we populate only origin + shipyard costs.
fn try_build_retrofit_bt_planned(
    current: &str,
    retrofit: &RetrofitPlan,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan as plan_search, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };
    // Retrofit-only LocMap — Source/Dest are unused by the
    // retrofit_catalog so their strings and costs don't matter.
    // Shipyard fields carry the real target.
    let mut map = LocMap::delivery(
        current.to_string(),
        current.to_string(), // Source placeholder (unused)
        current.to_string(), // Dest placeholder (unused)
        Commodity::Food,
        0,
        String::new(), // no contract
        0,
        0,
        0,
    );
    map.shipyard = Some(retrofit.shipyard_location.clone());
    map.refit_slot = Some(retrofit.slot);
    map.refit_slug = Some(retrofit.slug);
    map.cost_origin_to_shipyard = cost(current, &retrofit.shipyard_location);
    map.cost_source_to_shipyard = 0;
    map.cost_shipyard_to_dest = 0;

    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan_search(
        initial,
        |s| s.retrofitted && s.fuel_bucket >= 2,
        Operator::retrofit_catalog(),
        &map,
        16,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

#[allow(clippy::too_many_arguments)]
fn build_trade_run_bt(
    current: &str,
    buy_loc: &str,
    sell_loc: &str,
    commodity: Commodity,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    try_build_trade_run_bt_planned(
        current,
        buy_loc,
        sell_loc,
        commodity,
        fuel_bucket,
        registry,
        gate_pairs,
    )
    .unwrap_or_else(|| BtNode::action(ShipAction::Idle))
}

/// GOAP expansion: run the forward planner for a trade run. Goal =
/// `sold && fuel_bucket >= 2`. `trade_run_catalog` swaps DeliverCargo
/// for SellAll at the destination — no contract, just a market sell.
/// Takes the ship's real `fuel_bucket` so fuel-aware optimisations
/// can emerge: a flush ship skips refuels, a thirsty ship forces
/// one in at the first dockable stop.
#[allow(clippy::too_many_arguments)]
fn try_build_trade_run_bt_planned(
    current: &str,
    buy_loc: &str,
    sell_loc: &str,
    commodity: Commodity,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };
    let map = LocMap::trade_run(
        current.to_string(),
        buy_loc.to_string(),
        sell_loc.to_string(),
        commodity,
        TRADE_QTY_DEFAULT,
        cost(current, buy_loc),
        cost(buy_loc, sell_loc),
        cost(current, sell_loc),
    );
    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.sold && s.fuel_bucket >= 2,
        Operator::trade_run_catalog(),
        &map,
        20,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

/// Shared fuel-bucket cost estimator used by planned BT builders.
/// Walks the real leg sequence via the pathfinder and rolls the
/// summed distance into fuel buckets (~50 units per bucket).
fn estimate_fuel_bucket_cost(
    from: &str,
    to: &str,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> u8 {
    if from == to {
        return 0;
    }
    let ctx = crate::world::pathfinder::PathfinderCtx { registry, gate_pairs };
    let legs = match ctx.find_route(from, to) {
        Some(l) => l,
        None => return 1,
    };
    let total_distance: u32 = legs.iter().map(|l| l.distance.max(1)).sum();
    let buckets = ((total_distance as f32) / 50.0).ceil().max(1.0) as u32;
    buckets.min(10) as u8
}

/// Build a fulfill_delivery BT:
///   accept → travel to source → dock → refuel → buy → undock →
///   travel to destination → dock → deliver → undock
#[allow(clippy::too_many_arguments)]
fn build_fulfill_delivery_bt(
    current: &str,
    source: &str,
    destination: &str,
    commodity: Commodity,
    quantity: u32,
    contract_id: String,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    try_build_fulfill_delivery_bt_planned(
        current,
        source,
        destination,
        commodity,
        quantity,
        &contract_id,
        fuel_bucket,
        registry,
        gate_pairs,
    )
    .unwrap_or_else(|| BtNode::action(ShipAction::Idle))
}

/// GOAP MVP: run the forward planner to synthesise a delivery BT.
/// Returns `None` when the planner can't find a plan within its
/// depth cap (caller falls back to the hand-authored sequence).
///
/// This is where combined goals will live as the MVP expands. For
/// now the goal is simple `delivered == true AND fuel_bucket ≥ 2`
/// so the planner decides whether to insert a Refuel based on
/// travel-cost budgets — same emergent behaviour the hand-authored
/// builder has hardcoded, but derived rather than asserted.
#[allow(clippy::too_many_arguments)]
fn try_build_fulfill_delivery_bt_planned(
    current: &str,
    source: &str,
    destination: &str,
    commodity: Commodity,
    quantity: u32,
    contract_id: &str,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, LocMap, Loc, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };

    let map = LocMap::delivery(
        current.to_string(),
        source.to_string(),
        destination.to_string(),
        commodity,
        quantity,
        contract_id.to_string(),
        cost(current, source),
        cost(source, destination),
        cost(current, destination),
    );

    // Start state uses the ship's real fuel bucket so fuel-aware
    // optimisations can emerge — a flush ship skips unnecessary
    // refuels, a thirsty ship forces one at the first dockable
    // stop. The BT's real executors still re-check fuel at
    // execution time as a belt-and-braces.
    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.delivered && s.fuel_bucket >= 2,
        Operator::delivery_catalog(),
        &map,
        20,
    )?;

    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

/// Expand a planner-emitted action sequence into a real BT. Abstract
/// `Travel { destination }` steps get resolved to the actual multi-
/// leg pathfinder output (gate jumps etc.); `Dock` / `DockAtShipyard` /
/// `Undock` steps are wrapped with `DockDwell` so the visual pacing
/// matches the hand-authored builders. `AcceptContract` is prepended
/// only when the map carries a contract_id — trade-run plans skip
/// it entirely.
fn compile_plan_to_bt(
    plan_actions: &[ShipAction],
    map: &crate::ai::planner::LocMap,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    let mut steps: Vec<BtNode<ShipAction>> = Vec::with_capacity(plan_actions.len() * 2 + 2);
    if !map.contract_id.is_empty() {
        steps.push(BtNode::action(ShipAction::AcceptContract {
            contract_id: map.contract_id.clone(),
        }));
    }
    let mut current_loc = map.origin.clone();
    for a in plan_actions {
        match a {
            ShipAction::Travel { destination } => {
                for leg in route_actions(&current_loc, destination, registry, gate_pairs) {
                    steps.push(BtNode::action(leg));
                }
                current_loc = destination.clone();
            }
            ShipAction::Dock | ShipAction::DockAtShipyard => {
                steps.push(BtNode::action(a.clone()));
                steps.push(BtNode::action(ShipAction::DockDwell {
                    seconds: DOCK_ARRIVE_DWELL_SECS,
                }));
            }
            ShipAction::Undock => {
                steps.push(BtNode::action(ShipAction::DockDwell {
                    seconds: DOCK_DEPART_DWELL_SECS,
                }));
                steps.push(BtNode::action(ShipAction::Undock));
            }
            other => steps.push(BtNode::action(other.clone())),
        }
    }
    BtNode::sequence(steps)
}

/// GOAP expansion: synthesise a combined delivery+retrofit plan.
/// Returns `None` when the planner can't fold both goals within its
/// depth cap — caller falls back to the plain delivery builder,
/// meaning the retrofit runs as a separate plan later. This is the
/// first plan the hand-authored BTs literally cannot produce: a
/// single BT that picks up contract cargo, detours through a
/// shipyard for a refit, then delivers.
#[allow(clippy::too_many_arguments)]
fn try_build_fulfill_delivery_with_retrofit_planned(
    current: &str,
    source: &str,
    destination: &str,
    commodity: Commodity,
    quantity: u32,
    contract_id: &str,
    retrofit: &RetrofitPlan,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };

    let mut map = LocMap::delivery(
        current.to_string(),
        source.to_string(),
        destination.to_string(),
        commodity,
        quantity,
        contract_id.to_string(),
        cost(current, source),
        cost(source, destination),
        cost(current, destination),
    );
    map.shipyard = Some(retrofit.shipyard_location.clone());
    map.refit_slot = Some(retrofit.slot);
    map.refit_slug = Some(retrofit.slug);
    map.cost_origin_to_shipyard = cost(current, &retrofit.shipyard_location);
    map.cost_source_to_shipyard = cost(source, &retrofit.shipyard_location);
    map.cost_shipyard_to_dest = cost(&retrofit.shipyard_location, destination);

    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.delivered && s.retrofitted && s.fuel_bucket >= 2,
        Operator::delivery_catalog(),
        &map,
        28,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

/// GOAP: combined trade_run + retrofit. Mirror of the delivery+retrofit
/// variant for trade-class plans — ship buys at source, detours
/// through the shipyard for a refit, sells at dest. Uses
/// `trade_run_catalog` (SellAll at dest instead of DeliverCargo).
#[allow(clippy::too_many_arguments)]
fn try_build_trade_run_with_retrofit_planned(
    current: &str,
    buy_loc: &str,
    sell_loc: &str,
    commodity: Commodity,
    retrofit: &RetrofitPlan,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };

    let mut map = LocMap::trade_run(
        current.to_string(),
        buy_loc.to_string(),
        sell_loc.to_string(),
        commodity,
        TRADE_QTY_DEFAULT,
        cost(current, buy_loc),
        cost(buy_loc, sell_loc),
        cost(current, sell_loc),
    );
    map.shipyard = Some(retrofit.shipyard_location.clone());
    map.refit_slot = Some(retrofit.slot);
    map.refit_slug = Some(retrofit.slug);
    map.cost_origin_to_shipyard = cost(current, &retrofit.shipyard_location);
    map.cost_source_to_shipyard = cost(buy_loc, &retrofit.shipyard_location);
    map.cost_shipyard_to_dest = cost(&retrofit.shipyard_location, sell_loc);

    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.sold && s.retrofitted && s.fuel_bucket >= 2,
        Operator::trade_run_catalog(),
        &map,
        28,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}
