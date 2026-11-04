//! Faction components.
//!
//! Factions are small in count (~6) but referenced frequently by other agents.
//! Single combined component is fine — no cache-locality benefit to splitting.

use crate::ai::personality::Personality;
use bevy_ecs::prelude::{Component, Entity, World};
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct FactionColors {
    pub primary: String,
    pub secondary: String,
}

#[derive(Debug, Clone, Component)]
pub struct FactionData {
    pub id: String,
    pub name: String,
    pub faction_type: String,
    pub home_system: String,
    pub treasury: i64,
    pub personality: Personality,
    pub colors: FactionColors,
    /// Count of subsidy contracts currently on the board under this
    /// faction's name. Updated by `tick_factions` each cycle from the
    /// live board state.
    pub active_subsidies: u32,
    pub dirty: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct FactionSnapshot {
    pub id: String,
    pub name: String,
    pub faction_type: String,
    pub home_system: String,
    pub treasury: i64,
    pub colors: FactionColors,
    /// Active subsidy contracts this faction has on the board. Godot
    /// renders this in the faction ledger panel. Incremented when
    /// `tick_factions` posts a new subsidy, decremented as subsidies
    /// flow to Paid/Expired.
    pub active_subsidies: u32,
}

impl FactionSnapshot {
    pub fn build(data: &FactionData) -> Self {
        Self {
            id: data.id.clone(),
            name: data.name.clone(),
            faction_type: data.faction_type.clone(),
            home_system: data.home_system.clone(),
            treasury: data.treasury,
            colors: data.colors.clone(),
            active_subsidies: data.active_subsidies,
        }
    }
}

// ============================================================================
// Faction tick
// ============================================================================
//
// Every N base-ticks, each faction collects a tax from its owned facilities
// and adds it to its treasury. The rate and interval match Elixir's
// FactionAgent: 0.5% of each facility's taxable balance every 200 base-ticks.
// "Taxable" excludes a 1000-credit operating buffer so we never push a
// facility toward bankruptcy just by taxing it.
//
// Reputation decay and faction-posted subsidy contracts land in Phase 11e/f.

use crate::agents::facility::{FacilityIdentity, FacilityLocation, FacilityOperations};
use crate::agents::market::{MarketHistory, MarketIdentity};
use crate::economy::commodities::Commodity;
use crate::economy::contracts::ContractBoard;

/// Choose a real source market for any faction's delivery contract.
/// Own infrastructure wins when it can supply a full shipment; otherwise
/// fall back to trade with other factions. Never source from the destination.
/// Sorting ensures deterministic tie-breaking independent of HashMap order.
fn choose_logistics_source(
    supply_by_loc: &std::collections::HashMap<
        String,
        std::collections::HashMap<Commodity, f32>,
    >,
    member_locations: &[String],
    source_owners: &std::collections::HashMap<String, String>,
    relations: &crate::agents::faction_relations::FactionRelations,
    faction_id: &str,
    destination: &str,
    commodity: Commodity,
    minimum_available: f32,
) -> Option<String> {
    let mut candidates: Vec<(&String, f32, bool)> = supply_by_loc
        .iter()
        .filter_map(|(location, supply)| {
            if location == destination
                || !crate::agents::faction_relations::commerce_allowed(
                    relations,
                    faction_id,
                    source_owners.get(location).map(String::as_str).unwrap_or(""),
                )
            {
                return None;
            }
            let available = supply.get(&commodity).copied().unwrap_or(0.0);
            if !available.is_finite() || available < minimum_available {
                return None;
            }
            Some((location, available, member_locations.contains(location)))
        })
        .collect();
    candidates.sort_by(|a, b| {
        b.2.cmp(&a.2)
            .then_with(|| b.1.total_cmp(&a.1))
            .then_with(|| a.0.cmp(b.0))
    });
    candidates.first().map(|(location, _, _)| (*location).clone())
}

/// Personality only changes priorities, never the physical stock rules.
/// Example: a frontier faction can value keeping its fuel supply alive,
/// while a settled faction prioritises food and industrial materials.
fn shortage_priority(
    commodity: Commodity,
    shortage_ticks: u32,
    personality: Option<&Personality>,
) -> f32 {
    let preference = personality
        .and_then(|p| p.prefer_goals.get(&format!("secure_{}", commodity.as_str())))
        .copied()
        .unwrap_or(0.0)
        .clamp(0.0, 2.0);
    shortage_ticks as f32 * (1.0 + preference)
}

/// Base-tick interval for faction accounting. Matches Elixir's
/// `@tax_interval 200 * tick_multiplier()` in `faction_agent.ex`.
pub const FACTION_INTERVAL_BASE: u64 = 200;
/// Fraction of each facility's taxable credits moved to the faction each
/// cycle. Elixir used 0.5% — Rust bumps this to 2.5% because the demand
/// analyzer (19c) adds a construction-post sink the Elixir sim never
/// had, and the subsidy + bailout cadence at the old rate left every
/// faction permanently pinned at the $2k bailout floor within 2000
/// ticks. Paired with a less-frequent subsidy scan below.
pub const FACTION_TAX_RATE: f64 = 0.025;
/// Minimum credit buffer each facility keeps before tax applies. Matches
/// Elixir's `minimum_buffer = 1_000` in `facility_agent.ex:collect_tax`.
pub const FACILITY_TAX_BUFFER: i64 = 1_000;

// --- Subsidy posting (Phase 11e) ---
/// Base-tick interval for subsidy scans. Elixir used 30; Rust uses 60
/// so a given shortage only gets one subsidy posted per 60-base-tick
/// window instead of piling up 3 subsidies on the same starved market
/// within a few ticks of each other (each one costing a faction
/// several thousand credits).
pub const SUBSIDY_CHECK_INTERVAL_BASE: u64 = 60;
/// A commodity starts qualifying as "chronic" once its shortage_ticks
/// exceeds this threshold. Elixir: `@subsidy_trigger_ticks 30`.
pub const SUBSIDY_TRIGGER_TICKS: u32 = 30;
/// Require at least this many member markets in shortage before posting.
/// Elixir: `@min_facilities_short 2`.
pub const MIN_FACILITIES_SHORT: usize = 2;
/// Per-faction cap on posted subsidies. Elixir used 3; trimmed to 2
/// here so a faction's ongoing subsidy outlay is capped at ~10k
/// regardless of how many member markets are short. The demand
/// analyzer picks up chronic shortages the subsidy can't touch.
pub const MAX_ACTIVE_SUBSIDIES_PER_FACTION: u32 = 2;
/// Base subsidy payment before the dynamic multiplier. Elixir used
/// 2000; Rust trimmed to 800 as part of the Phase 19-tail treasury
/// rebalance. With the dynamic multiplier still scaling 1.25×–3.0×,
/// subsidies now cost 1000–2400 each — enough to be meaningful for a
/// courier ship but cheap enough that two concurrent subsidies don't
/// drain a faction from 30k → 2k inside a thousand ticks.
pub const SUBSIDY_BASE_PAYMENT: i64 = 800;
/// Subsidy order size. Elixir: `@subsidy_quantity 200`.
pub const SUBSIDY_QUANTITY: u32 = 200;
/// Multiplier floor / ceiling for dynamic subsidy payouts. Elixir ramps
/// from 1.25× at freshly-triggered to 3.0× at the hardest shortages.
pub const SUBSIDY_MIN_MULTIPLIER: f32 = 1.25;
pub const SUBSIDY_MAX_MULTIPLIER: f32 = 3.0;
/// Subsidy contract lifespan (base ticks). Matches Elixir's `500 × mult`.
pub const SUBSIDY_LIFESPAN_BASE: u64 = 500;

/// Phase 19c: demand analyzer posts a *construction* contract when a
/// commodity has been chronically short at a faction's member
/// location for this many ticks. Much higher bar than the subsidy
/// threshold — subsidy handles "we're out today", construction
/// handles "we've been out for ages, the fix is to build a producer."
pub const CONSTRUCTION_TRIGGER_TICKS: u32 = 600;

/// How often the demand analyzer runs (every N base-ticks). Spawning
/// facilities is consequential, so the cadence stays relatively
/// slow. 2026-04-24 tune: lowered 300 → 200 after the 20-minute
/// soak showed sustained 50-ship backlogs at producer hubs — a
/// shorter interval lets a faction respond to long-running
/// saturation sooner. Treasury rebalance (Phase 19-tail) already
/// gates on `CONSTRUCTION_MIN_TREASURY` so broke factions still
/// skip the post.
pub const CONSTRUCTION_CHECK_INTERVAL_BASE: u64 = 200;

/// Max active construction contracts a faction can have posted at
/// any time. 2026-04-24 tune: raised 1 → 2 for the same reason —
/// a faction with multiple chronic shortages shouldn't wait for
/// one build to finish before starting the next. Still low enough
/// that a struggling sector can't flood the board.
pub const MAX_ACTIVE_CONSTRUCTIONS_PER_FACTION: u32 = 2;

/// Base payment for a construction contract. Higher than subsidy
/// because the mission is bigger: you're literally ferrying 200 units
/// of a chronically-short commodity into a dying market. Trimmed from
/// 15k → 10k as part of the Phase 19-tail treasury rebalance — the
/// old value paired with the 18k min-treasury caused a single
/// construction post to drop a faction from ~25k to ~10k, and the
/// subsidy+bailout cadence finished the job within 1000 ticks.
pub const CONSTRUCTION_BASE_PAYMENT: i64 = 10_000;

/// Construction delivery headcount. Larger than subsidy so the
/// arriving shipment materially reshapes the destination market.
pub const CONSTRUCTION_QUANTITY: u32 = 200;

/// Construction contract lifespan (base ticks). Longer than subsidy
/// so big hulls across systems have time to arrive.
pub const CONSTRUCTION_LIFESPAN_BASE: u64 = 800;

/// Faction must hold at least this much treasury to self-fund a
/// construction payout. Sized to ~3× [`CONSTRUCTION_BASE_PAYMENT`]
/// so a single post still leaves the faction with a healthy cushion
/// for bailouts + subsidies — previously 18k, which paired with the
/// old 15k payment left factions one cycle from the $2k floor.
pub const CONSTRUCTION_MIN_TREASURY: i64 = 30_000;

/// Bundle D: territorial-control recompute interval (base ticks).
/// Body-level control changes only when facilities spawn / abandon /
/// transfer ownership — all rare events — so this can run much
/// slower than a per-tick scan. 50 base ticks lines up with the
/// other coarse maintenance passes.
pub const TERRITORIAL_RECOMPUTE_INTERVAL_BASE: u64 = 50;

/// Bundle D: subsidy payment multiplier when the destination is at a
/// contested body. Stacks on top of the existing shortage-age ramp —
/// the incumbent fights back with a richer payout so loyal couriers
/// keep choosing the contested zone over a quiet rival market.
pub const SUBSIDY_CONTESTED_MULTIPLIER: f32 = 1.4;

pub fn tick_factions(
    world: &mut World,
    contracts: &mut ContractBoard,
    events: &mut Vec<serde_json::Value>,
    system_control: &mut std::collections::HashMap<String, Option<String>>,
    relations: &crate::agents::faction_relations::FactionRelations,
    tick: u64,
    tick_multiplier: u32,
) {
    // --- Bundle D: territorial control derivation ---
    // Runs first in the cycle so subsidy + construction can read
    // fresh `BodyTerritory` state when scoring contested zones.
    let territory_interval = TERRITORIAL_RECOMPUTE_INTERVAL_BASE * tick_multiplier as u64;
    if territory_interval > 0 && tick % territory_interval == 0 {
        let updated = crate::agents::celestial_body::derive_territorial_control(world);
        *system_control = updated;
    }

    // --- Tax collection ---
    let tax_interval = FACTION_INTERVAL_BASE * tick_multiplier as u64;
    if tax_interval > 0 && tick % tax_interval == 0 {
        run_tax_cycle(world);
        // Right after taxing, bail out any member facility that's fallen
        // below the survival floor. Without this, once a facility's
        // credits hit 0 it can never post a contract, never get restocked,
        // and spirals into abandonment taking its recipe output with it —
        // which is the supply-chain collapse we saw at tick 13k.
        run_bailout_cycle(world);
    }

    // --- Subsidy posting ---
    let subsidy_interval = SUBSIDY_CHECK_INTERVAL_BASE * tick_multiplier as u64;
    if subsidy_interval > 0 && tick % subsidy_interval == 0 {
        run_subsidy_cycle(world, contracts, relations, tick, tick_multiplier);
    }

    // --- Construction demand analyzer (Phase 19c) ---
    // Extreme shortages → spawn a producer-class delivery contract.
    // Runs on its own interval, well-separated from subsidy cadence so
    // a single flow of "demand signal" doesn't bunch both responses on
    // the same tick.
    let construction_interval =
        CONSTRUCTION_CHECK_INTERVAL_BASE * tick_multiplier as u64;
    if construction_interval > 0 && tick % construction_interval == 0 {
        run_construction_cycle(world, contracts, events, relations, tick, tick_multiplier);
    }

    // Keep snapshot `active_subsidies` in sync — recalc from the board so
    // it drops as subsidies Paid/Expire too.
    refresh_active_subsidy_counts(world, contracts);
}

/// Faction treasury floor observed by bailouts. Bailouts won't drain
/// a faction below this while topping up distressed facilities.
/// Preserves capital for subsidy + construction posts later.
pub const FACTION_WORKING_CAPITAL_FLOOR: i64 = 10_000;

/// Faction treasury floor observed by subsidy posts. Lower than the
/// bailout floor so subsidies can still fire in the steady-state
/// "treasury at 10k, tax trickling in" regime — otherwise a faction
/// that settles at the bailout floor never posts another subsidy,
/// and the mechanism goes dormant.
pub const FACTION_SUBSIDY_FLOOR: i64 = 5_000;

/// Credits floor below which a facility is considered "in distress" and
/// its faction will wire enough money to get it back to posting-viable.
/// Trimmed from 3k → 500 because the old value triggered bailouts on
/// ~65/93 facilities fleet-wide each cycle — one bailout round cost
/// ~$370k across all factions vs. ~$5-10k of tax income, which pinned
/// every treasury at the floor permanently. At 500 credits the bailout
/// only catches facilities within a restock-cycle of abandonment.
pub const FACILITY_BAILOUT_FLOOR: i64 = 500;
/// Bailout top-up target. Sized to just enough runway to post one
/// small delivery contract and survive until its next tax cycle — not
/// "comfortable" credits. Paired with the lower floor above so a
/// bailout is an emergency airbag, not a monthly allowance.
pub const FACILITY_BAILOUT_TARGET: i64 = 2_000;

/// For each faction-owned facility whose credits dropped below
/// `FACILITY_BAILOUT_FLOOR`, transfer from faction treasury up to
/// `FACILITY_BAILOUT_TARGET`. Faction won't spend below a 2000-credit
/// treasury floor of its own — if a faction is itself broke, let the
/// facility fail.
fn run_bailout_cycle(world: &mut World) {
    // Pass 1: collect deficits per faction.
    #[derive(Clone)]
    struct Need {
        entity: Entity,
        faction_id: String,
        deficit: i64,
    }
    let needs: Vec<Need> = {
        let mut q = world.query::<(Entity, &FacilityIdentity, &FacilityOperations)>();
        q.iter(&world)
            .filter_map(|(e, id, ops)| {
                if id.faction_id.is_empty() || ops.credits >= FACILITY_BAILOUT_FLOOR {
                    return None;
                }
                Some(Need {
                    entity: e,
                    faction_id: id.faction_id.clone(),
                    deficit: FACILITY_BAILOUT_TARGET - ops.credits,
                })
            })
            .collect()
    };
    if needs.is_empty() {
        return;
    }

    // Pass 2: faction treasury by id.
    let mut treasury: std::collections::HashMap<String, i64> = {
        let mut q = world.query::<&FactionData>();
        q.iter(&world)
            .map(|d| (d.id.clone(), d.treasury))
            .collect()
    };

    // Pass 3: disburse — walk needs, subtract from treasury where the
    // faction can afford (keeping its own floor), and remember which
    // facilities got paid.
    // Bailouts honour the shared working-capital floor — same rule
    // that subsidy + construction posts observe.
    const FACTION_TREASURY_FLOOR: i64 = FACTION_WORKING_CAPITAL_FLOOR;
    let mut paid: Vec<(Entity, String, i64)> = Vec::new();
    for need in needs {
        let t = treasury.entry(need.faction_id.clone()).or_insert(0);
        let affordable = (*t - FACTION_TREASURY_FLOOR).max(0);
        if affordable <= 0 {
            continue;
        }
        let amount = need.deficit.min(affordable);
        if amount <= 0 {
            continue;
        }
        *t -= amount;
        paid.push((need.entity, need.faction_id, amount));
    }

    // Apply: credit facility, debit faction treasury.
    for (entity, fac_id, amount) in paid {
        if let Some(mut ops) = world.get_mut::<FacilityOperations>(entity) {
            ops.credits += amount;
            ops.dirty = true;
        }
        let mut q = world.query::<&mut FactionData>();
        for mut data in q.iter_mut(world) {
            if data.id == fac_id {
                data.treasury -= amount;
                data.dirty = true;
                break;
            }
        }
    }
}

/// Bundle D helper: is the body at `location_name` flagged contested?
/// Walks `FacilityIdentity` once to find the body the location maps
/// to, then reads that body's `BodyTerritory`. Returns false when the
/// location has no facilities or the body's territory hasn't been
/// derived yet (defensive — `BodyTerritory::default().contested`
/// would also be false, just less obviously).
fn dest_is_contested(world: &mut World, location_name: &str) -> bool {
    use crate::agents::celestial_body::{BodyIdentity, BodyTerritory};
    let body_id = {
        let mut q = world
            .query::<(&FacilityIdentity, &crate::agents::facility::FacilityLocation)>();
        q.iter(&world)
            .find(|(_, loc)| loc.location_name == location_name)
            .map(|(id, _)| id.body_id.clone())
    };
    let Some(body_id) = body_id else { return false };
    let mut q = world.query::<(&BodyIdentity, &BodyTerritory)>();
    q.iter(&world)
        .find(|(id, _)| id.body_id == body_id)
        .map(|(_, t)| t.contested)
        .unwrap_or(false)
}

fn run_tax_cycle(world: &mut World) {
    let mut owed_by_faction: std::collections::HashMap<String, i64> =
        std::collections::HashMap::new();
    {
        let mut q = world.query::<(&FacilityIdentity, &mut FacilityOperations)>();
        for (identity, mut ops) in q.iter_mut(world) {
            if identity.faction_id.is_empty() || ops.credits <= FACILITY_TAX_BUFFER {
                continue;
            }
            let taxable = ops.credits - FACILITY_TAX_BUFFER;
            let tax = ((taxable as f64) * FACTION_TAX_RATE) as i64;
            if tax > 0 {
                ops.credits -= tax;
                *owed_by_faction.entry(identity.faction_id.clone()).or_insert(0) += tax;
            }
        }
    }

    if owed_by_faction.is_empty() {
        return;
    }

    let mut q = world.query::<&mut FactionData>();
    for mut data in q.iter_mut(world) {
        if let Some(&amount) = owed_by_faction.get(&data.id) {
            data.treasury += amount;
            data.dirty = true;
        }
    }
}

/// Scan each faction's member markets for chronic shortages and post
/// subsidy contracts (high-paying delivery contracts) to pull in supply.
/// Matches Elixir's `maybe_post_subsidy_contract` flow.
fn run_subsidy_cycle(
    world: &mut World,
    contracts: &mut ContractBoard,
    relations: &crate::agents::faction_relations::FactionRelations,
    tick: u64,
    tick_multiplier: u32,
) {
    // Build faction_id → list of (location, shortage_ticks per commodity).
    // We look at each facility the faction owns, find the market at that
    // location, and aggregate its shortage_ticks map.
    #[derive(Clone, Default)]
    struct FactionShortage {
        /// commodity → (facility_count_short, max_shortage_ticks, location_of_max)
        by_commodity: std::collections::HashMap<Commodity, (usize, u32, String)>,
        member_locations: Vec<String>,
    }
    let mut shortage_by_faction: std::collections::HashMap<String, FactionShortage> =
        std::collections::HashMap::new();

    // location → (commodity → shortage_ticks) index.
    let market_shortage_by_loc: std::collections::HashMap<
        String,
        std::collections::HashMap<Commodity, u32>,
    > = {
        let mut q = world.query::<(&MarketIdentity, &MarketHistory)>();
        q.iter(&world)
            .map(|(id, hist)| (id.facility_location.clone(), hist.shortage_ticks.clone()))
            .collect()
    };

    {
        let mut q = world.query::<(&FacilityIdentity, &FacilityLocation)>();
        for (fac_id, fac_loc) in q.iter(&world) {
            if fac_id.faction_id.is_empty() {
                continue;
            }
            let loc = &fac_loc.location_name;
            let entry = shortage_by_faction
                .entry(fac_id.faction_id.clone())
                .or_default();
            // Several facilities at one dock still share ONE market.
            // Count that shortage once, not once per station/yard/factory.
            if entry.member_locations.contains(loc) {
                continue;
            }
            entry.member_locations.push(loc.clone());
            if let Some(short_map) = market_shortage_by_loc.get(loc) {
                for (&commodity, &shortage) in short_map {
                    if shortage < SUBSIDY_TRIGGER_TICKS {
                        continue;
                    }
                    let slot = entry.by_commodity.entry(commodity).or_default();
                    slot.0 += 1;
                    if shortage > slot.1 {
                        slot.1 = shortage;
                        slot.2 = loc.clone();
                    }
                }
            }
        }
    }

    // For each faction, find active subsidy count and pick a commodity+dest
    // to post. Post one per faction per cycle (keeps the board steady).
    #[derive(Clone)]
    struct SubsidyPlan {
        faction_id: String,
        commodity: Commodity,
        destination: String,
        source: String,
        payment: i64,
    }

    // Shared physical stock index. Factions may commission goods from
    // rivals only when their own usable depots cannot meet the order.
    let supply_by_loc: std::collections::HashMap<String, std::collections::HashMap<Commodity, f32>> = {
        let mut q = world.query::<(&MarketIdentity, &crate::agents::market::MarketPricing)>();
        q.iter(&world)
            .map(|(id, pricing)| (id.facility_location.clone(), pricing.supply.clone()))
            .collect()
    };
    let source_owners = crate::agents::faction_relations::market_controllers(world);
    let faction_profiles: std::collections::HashMap<String, Personality> = {
        let mut q = world.query::<&FactionData>();
        q.iter(&world).map(|d| (d.id.clone(), d.personality.clone())).collect()
    };

    let faction_ids: Vec<String> = shortage_by_faction.keys().cloned().collect();
    let mut plans: Vec<SubsidyPlan> = Vec::new();

    for faction_id in faction_ids {
        let info = shortage_by_faction.get(&faction_id).cloned().unwrap_or_default();
        // Count this faction's current board presence.
        let current_active = contracts
            .iter()
            .filter(|c| c.requestor_id == faction_id)
            .filter(|c| {
                matches!(
                    c.status,
                    crate::economy::contracts::ContractStatus::Posted
                        | crate::economy::contracts::ContractStatus::Accepted
                        | crate::economy::contracts::ContractStatus::PickedUp
                )
            })
            .count() as u32;
        if current_active >= MAX_ACTIVE_SUBSIDIES_PER_FACTION {
            continue;
        }

        // Pick the (commodity, destination) with the most chronic shortage
        // that meets MIN_FACILITIES_SHORT.
        let pick = info
            .by_commodity
            .iter()
            .filter(|(_, (cnt, _, _))| *cnt >= MIN_FACILITIES_SHORT)
            .max_by(|a, b| {
                let profile = faction_profiles.get(&faction_id);
                shortage_priority(*a.0, a.1.1, profile)
                    .total_cmp(&shortage_priority(*b.0, b.1.1, profile))
                    .then_with(|| a.0.as_str().cmp(b.0.as_str()))
            })
            .map(|(c, (_, max_short, dest))| (*c, *max_short, dest.clone()));
        let Some((commodity, max_shortage, destination)) = pick else {
            continue;
        };

        // Already subsidising this exact destination+commodity? Skip.
        let already = contracts.iter().any(|c| {
            c.requestor_id == faction_id
                && c.commodity == commodity
                && c.destination_location == destination
                && matches!(
                    c.status,
                    crate::economy::contracts::ContractStatus::Posted
                        | crate::economy::contracts::ContractStatus::Accepted
                        | crate::economy::contracts::ContractStatus::PickedUp
                )
        });
        if already {
            continue;
        }

        let source = choose_logistics_source(
            &supply_by_loc,
            &info.member_locations,
            &source_owners,
            relations,
            &faction_id,
            &destination,
            commodity,
            SUBSIDY_QUANTITY as f32,
        );
        let Some(source) = source else { continue };
        if source == destination {
            continue;
        }

        // Dynamic multiplier: 1.25× freshly-triggered → 3.0× hardest shortage.
        // `(max_shortage - trigger) / 100` linearly ramps over 100 ticks past
        // the onset point.
        let over = (max_shortage.saturating_sub(SUBSIDY_TRIGGER_TICKS)) as f32;
        let ramp = (over / 100.0).min(SUBSIDY_MAX_MULTIPLIER - SUBSIDY_MIN_MULTIPLIER);
        let mut multiplier = SUBSIDY_MIN_MULTIPLIER + ramp;
        // Bundle D: contested-body bump. The incumbent posts a richer
        // payout when the destination body has rival facilities, so
        // loyal couriers stay engaged with the squeeze rather than
        // peel off to easier markets. Stacks multiplicatively with the
        // shortage-age ramp.
        if dest_is_contested(world, &destination) {
            multiplier *= SUBSIDY_CONTESTED_MULTIPLIER;
        }
        let payment = ((SUBSIDY_BASE_PAYMENT as f32) * multiplier) as i64;

        plans.push(SubsidyPlan {
            faction_id,
            commodity,
            destination,
            source,
            payment,
        });
    }

    // Apply plans: debit treasury, post contract.
    let lifespan = SUBSIDY_LIFESPAN_BASE * tick_multiplier as u64;
    for plan in plans {
        // Check + debit treasury.
        // Keep a working-capital floor so subsidies can't drain
        // a faction to zero — mirrors the same floor bailouts
        // observe. Without this guard a busy faction could
        // post 2 subsidies at a multiplier spike and go broke
        // before the next tax cycle replenishes.
        let afford: Option<Entity> = {
            let mut q = world.query::<(Entity, &FactionData)>();
            q.iter(&world)
                .find(|(_, d)| {
                    d.id == plan.faction_id
                        && d.treasury.saturating_sub(FACTION_SUBSIDY_FLOOR) >= plan.payment
                })
                .map(|(e, _)| e)
        };
        let Some(entity) = afford else { continue };
        if let Some(mut data) = world.get_mut::<FactionData>(entity) {
            data.treasury -= plan.payment;
            data.active_subsidies = data.active_subsidies.saturating_add(1);
            data.dirty = true;
        }
        contracts.post_subsidy(
            plan.faction_id,
            plan.commodity,
            SUBSIDY_QUANTITY,
            plan.source,
            plan.destination,
            plan.payment,
            tick,
            lifespan,
        );
    }
}

/// Phase 19c: demand analyzer. Chronic-shortage detection — mirrors
/// the subsidy cycle's structure but fires on a much higher threshold
/// and posts a [`ContractType::Construction`] contract instead of a
/// subsidy. The delivered commodity lands at the starved destination
/// like a regular delivery; a follow-up commit will also spawn a
/// producer facility there on successful Paid.
///
/// Constraints:
/// - faction treasury ≥ [`CONSTRUCTION_MIN_TREASURY`] (won't bankrupt)
/// - at least one member-location market has `shortage_ticks` ≥
///   [`CONSTRUCTION_TRIGGER_TICKS`] (600 ticks = very long haul)
/// - faction has < [`MAX_ACTIVE_CONSTRUCTIONS_PER_FACTION`] currently
///   on the board
/// - one construction per faction per cycle — the same shortage can
///   warrant re-posting on the next interval if nothing took the
///   contract
fn run_construction_cycle(
    world: &mut World,
    contracts: &mut ContractBoard,
    events: &mut Vec<serde_json::Value>,
    relations: &crate::agents::faction_relations::FactionRelations,
    tick: u64,
    tick_multiplier: u32,
) {
    // Reuse the same "faction → worst-shortage commodity/destination"
    // shape the subsidy cycle builds, but with the higher threshold.
    #[derive(Clone, Default)]
    struct FactionShortage {
        by_commodity: std::collections::HashMap<Commodity, (usize, u32, String)>,
        member_locations: Vec<String>,
    }
    let mut shortage_by_faction: std::collections::HashMap<String, FactionShortage> =
        std::collections::HashMap::new();

    let market_shortage_by_loc: std::collections::HashMap<
        String,
        std::collections::HashMap<Commodity, u32>,
    > = {
        let mut q = world.query::<(&MarketIdentity, &MarketHistory)>();
        q.iter(&world)
            .map(|(id, hist)| (id.facility_location.clone(), hist.shortage_ticks.clone()))
            .collect()
    };

    {
        let mut q = world.query::<(&FacilityIdentity, &FacilityLocation)>();
        for (fac_id, fac_loc) in q.iter(&world) {
            if fac_id.faction_id.is_empty() {
                continue;
            }
            let loc = &fac_loc.location_name;
            let entry = shortage_by_faction
                .entry(fac_id.faction_id.clone())
                .or_default();
            // Several facilities at one dock still share ONE market.
            // Count that shortage once, not once per station/yard/factory.
            if entry.member_locations.contains(loc) {
                continue;
            }
            entry.member_locations.push(loc.clone());
            if let Some(short_map) = market_shortage_by_loc.get(loc) {
                for (&commodity, &shortage) in short_map {
                    if shortage < CONSTRUCTION_TRIGGER_TICKS {
                        continue;
                    }
                    let slot = entry.by_commodity.entry(commodity).or_default();
                    slot.0 += 1;
                    if shortage > slot.1 {
                        slot.1 = shortage;
                        slot.2 = loc.clone();
                    }
                }
            }
        }
    }

    #[derive(Clone)]
    struct Plan {
        faction_id: String,
        commodity: Commodity,
        destination: String,
        source: String,
        payment: i64,
    }

    let supply_by_loc: std::collections::HashMap<String, std::collections::HashMap<Commodity, f32>> = {
        let mut q = world.query::<(&MarketIdentity, &crate::agents::market::MarketPricing)>();
        q.iter(&world)
            .map(|(id, pricing)| (id.facility_location.clone(), pricing.supply.clone()))
            .collect()
    };

    let source_owners = crate::agents::faction_relations::market_controllers(world);
    let faction_profiles: std::collections::HashMap<String, Personality> = {
        let mut q = world.query::<&FactionData>();
        q.iter(&world).map(|d| (d.id.clone(), d.personality.clone())).collect()
    };
    let faction_ids: Vec<String> = shortage_by_faction.keys().cloned().collect();
    let mut plans: Vec<Plan> = Vec::new();

    for faction_id in faction_ids {
        let info = shortage_by_faction.get(&faction_id).cloned().unwrap_or_default();

        let current_active = contracts
            .iter()
            .filter(|c| {
                c.requestor_id == faction_id
                    && c.contract_type == crate::economy::contracts::ContractType::Construction
            })
            .filter(|c| {
                matches!(
                    c.status,
                    crate::economy::contracts::ContractStatus::Posted
                        | crate::economy::contracts::ContractStatus::Accepted
                        | crate::economy::contracts::ContractStatus::PickedUp
                )
            })
            .count() as u32;
        if current_active >= MAX_ACTIVE_CONSTRUCTIONS_PER_FACTION {
            continue;
        }

        let pick = info
            .by_commodity
            .iter()
            .filter(|(_, (cnt, _, _))| *cnt >= 1) // any facility short
            .max_by(|a, b| {
                let profile = faction_profiles.get(&faction_id);
                shortage_priority(*a.0, a.1.1, profile)
                    .total_cmp(&shortage_priority(*b.0, b.1.1, profile))
                    .then_with(|| a.0.as_str().cmp(b.0.as_str()))
            })
            .map(|(c, (_, _, dest))| (*c, dest.clone()));
        let Some((commodity, destination)) = pick else {
            continue;
        };

        // Already posting this exact destination+commodity? Skip.
        let already = contracts.iter().any(|c| {
            c.requestor_id == faction_id
                && c.commodity == commodity
                && c.destination_location == destination
                && c.contract_type == crate::economy::contracts::ContractType::Construction
                && matches!(
                    c.status,
                    crate::economy::contracts::ContractStatus::Posted
                        | crate::economy::contracts::ContractStatus::Accepted
                        | crate::economy::contracts::ContractStatus::PickedUp
                )
        });
        if already {
            continue;
        }

        let source = choose_logistics_source(
            &supply_by_loc,
            &info.member_locations,
            &source_owners,
            relations,
            &faction_id,
            &destination,
            commodity,
            CONSTRUCTION_QUANTITY as f32,
        );
        let Some(source) = source else { continue };
        plans.push(Plan {
            faction_id,
            commodity,
            destination,
            source,
            payment: CONSTRUCTION_BASE_PAYMENT,
        });
    }

    // Apply plans: treasury debit, spawn site if missing, post contract.
    let lifespan = CONSTRUCTION_LIFESPAN_BASE * tick_multiplier as u64;
    for plan in plans {
        let afford: Option<Entity> = {
            let mut q = world.query::<(Entity, &FactionData)>();
            q.iter(&world)
                .find(|(_, d)| {
                    d.id == plan.faction_id && d.treasury >= CONSTRUCTION_MIN_TREASURY
                })
                .map(|(e, _)| e)
        };
        let Some(entity) = afford else { continue };
        if let Some(mut data) = world.get_mut::<FactionData>(entity) {
            data.treasury -= plan.payment;
            data.dirty = true;
        }
        // Phase 19c-b: spawn a ConstructionSite at the destination
        // before posting the contract. Multiple contracts can target
        // the same site (three 200-unit deliveries = 600 units total
        // = one finished facility) — the delivery apply phase routes
        // progress accrual by (location, commodity).
        ensure_site_spawned(
            world,
            events,
            &plan.faction_id,
            plan.commodity,
            &plan.destination,
            tick,
        );
        contracts.post_construction(
            plan.faction_id.clone(),
            Some(plan.faction_id),
            plan.commodity,
            CONSTRUCTION_QUANTITY,
            plan.source,
            plan.destination,
            plan.payment,
            tick,
            lifespan,
        );
    }
}

/// Spawn a construction-site entity at `plan.destination` if none
/// already exists for this commodity. Picks the body by looking at
/// any existing facility at the destination; picks the position via
/// the same `facility_offset_position` hash so the site visually
/// sits where the real facility will materialise.
fn ensure_site_spawned(
    world: &mut World,
    events: &mut Vec<serde_json::Value>,
    faction_id: &str,
    commodity: Commodity,
    destination: &str,
    tick: u64,
) {
    use crate::agents::celestial_body::{BodyIdentity, BodyOrbit};
    use crate::agents::construction::{
        self, ConstructionSite, CONSTRUCTION_PROGRESS_REQUIRED,
    };

    if construction::site_exists_for(world, destination, commodity) {
        return;
    }

    // Pick body from any facility at the destination. Without a body
    // we can't place the site; skip.
    let body_id = {
        use crate::agents::facility::{FacilityIdentity, FacilityLocation};
        let mut q = world.query::<(&FacilityIdentity, &FacilityLocation)>();
        q.iter(&world)
            .find(|(_, loc)| loc.location_name == destination)
            .map(|(id, _)| id.body_id.clone())
    };
    let Some(body_id) = body_id else { return };

    let body_center = {
        let mut q = world.query::<(&BodyIdentity, &BodyOrbit)>();
        q.iter(&world)
            .find(|(id, _)| id.body_id == body_id)
            .map(|(_, orbit)| orbit.universe_position())
    };
    let Some(body_center) = body_center else { return };

    let site_id = format!("site-{}-{}-{}", commodity.as_str(), destination, tick);
    let position =
        crate::agents::facility::facility_offset_position(body_center, &site_id);
    let facility_type = construction::facility_type_for_commodity(commodity);

    let name = format!(
        "{} {} Works (under construction)",
        human_prefix(destination),
        commodity.as_str().to_ascii_uppercase()
    );

    let site = ConstructionSite {
        id: site_id.clone(),
        name: name.clone(),
        facility_type: facility_type.to_string(),
        faction_id: faction_id.to_string(),
        body_id,
        location_name: destination.to_string(),
        commodity,
        progress_delivered: 0,
        progress_required: CONSTRUCTION_PROGRESS_REQUIRED,
        position,
        spawned_at_tick: tick,
        completed: false,
        dirty: true,
    };
    world.spawn((site,));

    events.push(serde_json::json!({
        "kind": "construction_site_started",
        "site_id": site_id,
        "name": name,
        "facility_type": facility_type,
        "location": destination,
        "commodity": commodity.as_str(),
        "required": CONSTRUCTION_PROGRESS_REQUIRED,
    }));
}

/// Tiny helper — turns a location slug like "kuiper-station" into
/// "Kuiper" for the site's display name. Not perfect for multi-word
/// slugs but good enough for the "under construction" label.
fn human_prefix(slug: &str) -> String {
    slug.split('-')
        .next()
        .map(|s| {
            let mut c = s.chars();
            match c.next() {
                Some(ch) => ch.to_ascii_uppercase().to_string() + c.as_str(),
                None => String::new(),
            }
        })
        .unwrap_or_default()
}


/// Recount each faction's active-subsidy count from the live contract board.
/// Runs after subsidy posting so the count reflects any deliveries that
/// closed (Paid) or timed out (Expired) since last cycle.
fn refresh_active_subsidy_counts(world: &mut World, contracts: &ContractBoard) {
    use crate::economy::contracts::ContractStatus;
    let mut counts: std::collections::HashMap<String, u32> = std::collections::HashMap::new();
    for c in contracts.iter() {
        if matches!(
            c.status,
            ContractStatus::Posted | ContractStatus::Accepted | ContractStatus::PickedUp
        ) {
            *counts.entry(c.requestor_id.clone()).or_insert(0) += 1;
        }
    }
    let mut q = world.query::<&mut FactionData>();
    for mut data in q.iter_mut(world) {
        let n = counts.get(&data.id).copied().unwrap_or(0);
        if data.active_subsidies != n {
            data.active_subsidies = n;
            data.dirty = true;
        }
    }
}

// Genesis shared-economy guard: these rules apply equally to every faction
// and never depend on a special pirate/Genesis identifier.
#[cfg(test)]
mod genesis_faction_logistics_tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn prefers_owned_physical_stock_over_rival_even_when_rival_has_more() {
        let mut markets = HashMap::new();
        markets.insert("own-mine".into(), HashMap::from([(Commodity::Gas, 240.0)]));
        markets.insert("rival-mine".into(), HashMap::from([(Commodity::Gas, 900.0)]));
        markets.insert("own-base".into(), HashMap::from([(Commodity::Gas, 8.0)]));
        let members = vec!["own-mine".into(), "own-base".into()];
        let owners = HashMap::from([
            ("own-mine".into(), "own".into()),
            ("own-base".into(), "own".into()),
            ("rival-mine".into(), "rival".into()),
        ]);
        let relations = crate::agents::faction_relations::FactionRelations::new();
        assert_eq!(
            choose_logistics_source(&markets, &members, &owners, &relations, "own", "own-base", Commodity::Gas, 200.0),
            Some("own-mine".to_string())
        );
    }

    #[test]
    fn buys_from_rival_only_if_own_depots_cannot_fill_delivery() {
        let mut markets = HashMap::new();
        markets.insert("own-mine".into(), HashMap::from([(Commodity::Gas, 199.0)]));
        markets.insert("rival-mine".into(), HashMap::from([(Commodity::Gas, 240.0)]));
        let members = vec!["own-mine".into(), "own-base".into()];
        let owners = HashMap::from([
            ("own-mine".into(), "own".into()),
            ("own-base".into(), "own".into()),
            ("rival-mine".into(), "rival".into()),
        ]);
        let relations = crate::agents::faction_relations::FactionRelations::new();
        assert_eq!(
            choose_logistics_source(&markets, &members, &owners, &relations, "own", "own-base", Commodity::Gas, 200.0),
            Some("rival-mine".to_string())
        );
        assert_eq!(
            choose_logistics_source(&markets, &members, &owners, &relations, "own", "rival-mine", Commodity::Gas, 200.0),
            None
        );
    }

    #[test]
    fn empty_or_unfunded_sources_never_spawn_free_goods() {
        let mut markets = HashMap::new();
        markets.insert("mine".into(), HashMap::from([(Commodity::Gas, 0.0)]));
        assert_eq!(
            choose_logistics_source(&markets, &[], &HashMap::new(), &crate::agents::faction_relations::FactionRelations::new(), "own", "base", Commodity::Gas, 200.0),
            None
        );
    }

    #[test]
    fn hostile_sources_are_excluded_even_when_they_are_richer() {
        let markets = HashMap::from([
            ("own-depot".into(), HashMap::from([(Commodity::Ore, 180.0)])),
            ("enemy-depot".into(), HashMap::from([(Commodity::Ore, 3000.0)])),
            ("neutral-depot".into(), HashMap::from([(Commodity::Ore, 250.0)])),
        ]);
        let owners = HashMap::from([
            ("own-depot".into(), "own".into()),
            ("enemy-depot".into(), "enemy".into()),
            ("neutral-depot".into(), "neutral".into()),
        ]);
        let mut relations = crate::agents::faction_relations::FactionRelations::new();
        relations.set_state("own", "enemy", -100,
            crate::agents::faction_relations::TreatyKind::War, 0);
        assert_eq!(
            choose_logistics_source(&markets, &["own-depot".into()], &owners, &relations,
                "own", "home", Commodity::Ore, 200.0),
            Some("neutral-depot".to_string())
        );
    }

    #[test]
    fn faction_preferences_change_goals_not_supply() {
        let mut civilian = Personality::balanced_trader();
        let mut frontier = Personality::balanced_trader();
        civilian.prefer_goals.insert("secure_food".to_string(), 0.8);
        frontier.prefer_goals.insert("secure_fuel".to_string(), 1.2);
        assert!(
            shortage_priority(Commodity::Food, 80, Some(&civilian))
                > shortage_priority(Commodity::Fuel, 80, Some(&civilian))
        );
        assert!(
            shortage_priority(Commodity::Fuel, 80, Some(&frontier))
                > shortage_priority(Commodity::Food, 80, Some(&frontier))
        );
    }
}
