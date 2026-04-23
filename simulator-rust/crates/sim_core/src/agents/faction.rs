//! Faction components.
//!
//! Factions are small in count (~6) but referenced frequently by other agents.
//! Single combined component is fine — no cache-locality benefit to splitting.

use crate::ai::personality::Personality;
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct FactionColors {
    pub primary: String,
    pub secondary: String,
}

#[derive(Debug, Clone)]
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

/// Base-tick interval for faction accounting. Matches Elixir's
/// `@tax_interval 200 * tick_multiplier()` in `faction_agent.ex`.
pub const FACTION_INTERVAL_BASE: u64 = 200;
/// Fraction of each facility's taxable credits moved to the faction each
/// cycle. Matches Elixir `@tax_rate 0.005` (0.5%).
pub const FACTION_TAX_RATE: f64 = 0.005;
/// Minimum credit buffer each facility keeps before tax applies. Matches
/// Elixir's `minimum_buffer = 1_000` in `facility_agent.ex:collect_tax`.
pub const FACILITY_TAX_BUFFER: i64 = 1_000;

// --- Subsidy posting (Phase 11e) ---
/// Base-tick interval for subsidy scans. Matches Elixir's
/// `@subsidy_check_interval 30 * tick_multiplier()`.
pub const SUBSIDY_CHECK_INTERVAL_BASE: u64 = 30;
/// A commodity starts qualifying as "chronic" once its shortage_ticks
/// exceeds this threshold. Elixir: `@subsidy_trigger_ticks 30`.
pub const SUBSIDY_TRIGGER_TICKS: u32 = 30;
/// Require at least this many member markets in shortage before posting.
/// Elixir: `@min_facilities_short 2`.
pub const MIN_FACILITIES_SHORT: usize = 2;
/// Per-faction cap on posted subsidies. Elixir: `@max_active_subsidies 3`.
pub const MAX_ACTIVE_SUBSIDIES_PER_FACTION: u32 = 3;
/// Base subsidy payment before the dynamic multiplier. Elixir: `2_000`.
pub const SUBSIDY_BASE_PAYMENT: i64 = 2_000;
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

/// How often the demand analyzer runs (every N base-ticks). Rare —
/// spawning facilities is a consequential act. Cadence lives on the
/// faction tick alongside subsidy.
pub const CONSTRUCTION_CHECK_INTERVAL_BASE: u64 = 100;

/// Max active construction contracts a faction can have posted at
/// any time. One keeps the board focused; beyond that a struggling
/// sector would flood the ticker with the same plea.
pub const MAX_ACTIVE_CONSTRUCTIONS_PER_FACTION: u32 = 1;

/// Base payment for a construction contract. Much higher than
/// subsidy because the mission is bigger: you're literally ferrying
/// 200 units of a chronically-short commodity into a dying market.
pub const CONSTRUCTION_BASE_PAYMENT: i64 = 15_000;

/// Construction delivery headcount. Larger than subsidy so the
/// arriving shipment materially reshapes the destination market.
pub const CONSTRUCTION_QUANTITY: u32 = 200;

/// Construction contract lifespan (base ticks). Longer than subsidy
/// so big hulls across systems have time to arrive.
pub const CONSTRUCTION_LIFESPAN_BASE: u64 = 800;

/// Faction must hold at least this much treasury to self-fund a
/// construction payout. Avoids bankrupting broke factions.
pub const CONSTRUCTION_MIN_TREASURY: i64 = 18_000;

pub fn tick_factions(
    world: &mut hecs::World,
    contracts: &mut ContractBoard,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
    tick_multiplier: u32,
) {
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
        run_subsidy_cycle(world, contracts, tick, tick_multiplier);
    }

    // --- Construction demand analyzer (Phase 19c) ---
    // Extreme shortages → spawn a producer-class delivery contract.
    // Runs on its own interval, well-separated from subsidy cadence so
    // a single flow of "demand signal" doesn't bunch both responses on
    // the same tick.
    let construction_interval =
        CONSTRUCTION_CHECK_INTERVAL_BASE * tick_multiplier as u64;
    if construction_interval > 0 && tick % construction_interval == 0 {
        run_construction_cycle(world, contracts, events, tick, tick_multiplier);
    }

    // Keep snapshot `active_subsidies` in sync — recalc from the board so
    // it drops as subsidies Paid/Expire too.
    refresh_active_subsidy_counts(world, contracts);
}

/// Credits floor below which a facility is considered "in distress" and
/// its faction will wire enough money to get it back to posting-viable.
/// Sized to roughly one delivery contract so the bailout only fires
/// when the facility truly can't post.
pub const FACILITY_BAILOUT_FLOOR: i64 = 3_000;
/// Bailout top-up target. Moderate — enough to post one contract plus
/// a small buffer. Keeping this small means faction treasuries last
/// longer across the bailout budget; scaling up the target just drains
/// factions faster without the economy catching up.
pub const FACILITY_BAILOUT_TARGET: i64 = 6_000;

/// For each faction-owned facility whose credits dropped below
/// `FACILITY_BAILOUT_FLOOR`, transfer from faction treasury up to
/// `FACILITY_BAILOUT_TARGET`. Faction won't spend below a 2000-credit
/// treasury floor of its own — if a faction is itself broke, let the
/// facility fail.
fn run_bailout_cycle(world: &mut hecs::World) {
    // Pass 1: collect deficits per faction.
    #[derive(Clone)]
    struct Need {
        entity: hecs::Entity,
        faction_id: String,
        deficit: i64,
    }
    let needs: Vec<Need> = world
        .query::<(&FacilityIdentity, &FacilityOperations)>()
        .iter()
        .filter_map(|(e, (id, ops))| {
            if id.faction_id.is_empty() || ops.credits >= FACILITY_BAILOUT_FLOOR {
                return None;
            }
            Some(Need {
                entity: e,
                faction_id: id.faction_id.clone(),
                deficit: FACILITY_BAILOUT_TARGET - ops.credits,
            })
        })
        .collect();
    if needs.is_empty() {
        return;
    }

    // Pass 2: faction treasury by id.
    let mut treasury: std::collections::HashMap<String, i64> = world
        .query::<&FactionData>()
        .iter()
        .map(|(_, d)| (d.id.clone(), d.treasury))
        .collect();

    // Pass 3: disburse — walk needs, subtract from treasury where the
    // faction can afford (keeping its own floor), and remember which
    // facilities got paid.
    const FACTION_TREASURY_FLOOR: i64 = 2_000;
    let mut paid: Vec<(hecs::Entity, String, i64)> = Vec::new();
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
        if let Ok(mut ops) = world.get::<&mut FacilityOperations>(entity) {
            ops.credits += amount;
            ops.dirty = true;
        }
        for (_, data) in world.query_mut::<&mut FactionData>() {
            if data.id == fac_id {
                data.treasury -= amount;
                data.dirty = true;
                break;
            }
        }
    }
}

fn run_tax_cycle(world: &mut hecs::World) {
    let mut owed_by_faction: std::collections::HashMap<String, i64> =
        std::collections::HashMap::new();
    for (_e, (identity, ops)) in world
        .query::<(&FacilityIdentity, &mut FacilityOperations)>()
        .iter()
    {
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

    if owed_by_faction.is_empty() {
        return;
    }

    for (_e, data) in world.query_mut::<&mut FactionData>() {
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
    world: &mut hecs::World,
    contracts: &mut ContractBoard,
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
    > = world
        .query::<(&MarketIdentity, &MarketHistory)>()
        .iter()
        .map(|(_e, (id, hist))| (id.facility_location.clone(), hist.shortage_ticks.clone()))
        .collect();

    for (_e, (fac_id, fac_loc)) in world
        .query::<(&FacilityIdentity, &FacilityLocation)>()
        .iter()
    {
        if fac_id.faction_id.is_empty() {
            continue;
        }
        let loc = &fac_loc.location_name;
        let entry = shortage_by_faction
            .entry(fac_id.faction_id.clone())
            .or_default();
        if !entry.member_locations.contains(loc) {
            entry.member_locations.push(loc.clone());
        }
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

    // Source = highest-supply location OUTSIDE the faction's own member set.
    // If none, fall back to any highest-supply location.
    let supply_by_loc: std::collections::HashMap<String, std::collections::HashMap<Commodity, f32>> = world
        .query::<(&MarketIdentity, &crate::agents::market::MarketPricing)>()
        .iter()
        .map(|(_e, (id, pricing))| (id.facility_location.clone(), pricing.supply.clone()))
        .collect();

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
            .max_by_key(|(_, (_, max_short, _))| *max_short)
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

        // Source selection: highest supply, preferring non-member locations.
        let source_pref = supply_by_loc
            .iter()
            .filter(|(loc, supply)| {
                !info.member_locations.contains(loc)
                    && supply.get(&commodity).copied().unwrap_or(0.0) > 100.0
            })
            .max_by(|(_, a), (_, b)| {
                let av = a.get(&commodity).copied().unwrap_or(0.0);
                let bv = b.get(&commodity).copied().unwrap_or(0.0);
                av.partial_cmp(&bv).unwrap_or(std::cmp::Ordering::Equal)
            })
            .map(|(loc, _)| loc.clone());
        let source = source_pref
            .or_else(|| {
                supply_by_loc
                    .iter()
                    .max_by(|(_, a), (_, b)| {
                        let av = a.get(&commodity).copied().unwrap_or(0.0);
                        let bv = b.get(&commodity).copied().unwrap_or(0.0);
                        av.partial_cmp(&bv).unwrap_or(std::cmp::Ordering::Equal)
                    })
                    .map(|(loc, _)| loc.clone())
            });
        let Some(source) = source else { continue };
        if source == destination {
            continue;
        }

        // Dynamic multiplier: 1.25× freshly-triggered → 3.0× hardest shortage.
        // `(max_shortage - trigger) / 100` linearly ramps over 100 ticks past
        // the onset point.
        let over = (max_shortage.saturating_sub(SUBSIDY_TRIGGER_TICKS)) as f32;
        let ramp = (over / 100.0).min(SUBSIDY_MAX_MULTIPLIER - SUBSIDY_MIN_MULTIPLIER);
        let multiplier = SUBSIDY_MIN_MULTIPLIER + ramp;
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
        let afford = {
            let mut q = world
                .query::<&mut FactionData>()
                .iter()
                .find(|(_, d)| d.id == plan.faction_id)
                .map(|(e, _)| e);
            q = q.filter(|e| {
                world
                    .get::<&FactionData>(*e)
                    .map(|d| d.treasury >= plan.payment)
                    .unwrap_or(false)
            });
            q
        };
        let Some(entity) = afford else { continue };
        if let Ok(mut data) = world.get::<&mut FactionData>(entity) {
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
    world: &mut hecs::World,
    contracts: &mut ContractBoard,
    events: &mut Vec<serde_json::Value>,
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
    > = world
        .query::<(&MarketIdentity, &MarketHistory)>()
        .iter()
        .map(|(_e, (id, hist))| (id.facility_location.clone(), hist.shortage_ticks.clone()))
        .collect();

    for (_e, (fac_id, fac_loc)) in world
        .query::<(&FacilityIdentity, &FacilityLocation)>()
        .iter()
    {
        if fac_id.faction_id.is_empty() {
            continue;
        }
        let loc = &fac_loc.location_name;
        let entry = shortage_by_faction
            .entry(fac_id.faction_id.clone())
            .or_default();
        if !entry.member_locations.contains(loc) {
            entry.member_locations.push(loc.clone());
        }
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

    #[derive(Clone)]
    struct Plan {
        faction_id: String,
        commodity: Commodity,
        destination: String,
        source: String,
        payment: i64,
    }

    let supply_by_loc: std::collections::HashMap<String, std::collections::HashMap<Commodity, f32>> = world
        .query::<(&MarketIdentity, &crate::agents::market::MarketPricing)>()
        .iter()
        .map(|(_e, (id, pricing))| (id.facility_location.clone(), pricing.supply.clone()))
        .collect();

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
            .max_by_key(|(_, (_, max_short, _))| *max_short)
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

        // Source = highest-supply location with >= 200 units available.
        let source = supply_by_loc
            .iter()
            .filter(|(_, supply)| supply.get(&commodity).copied().unwrap_or(0.0) >= 200.0)
            .max_by(|(_, a), (_, b)| {
                let av = a.get(&commodity).copied().unwrap_or(0.0);
                let bv = b.get(&commodity).copied().unwrap_or(0.0);
                av.partial_cmp(&bv).unwrap_or(std::cmp::Ordering::Equal)
            })
            .map(|(loc, _)| loc.clone());
        let Some(source) = source else { continue };
        if source == destination {
            continue;
        }

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
        let afford = world
            .query::<&FactionData>()
            .iter()
            .find(|(_, d)| d.id == plan.faction_id && d.treasury >= CONSTRUCTION_MIN_TREASURY)
            .map(|(e, _)| e);
        let Some(entity) = afford else { continue };
        if let Ok(mut data) = world.get::<&mut FactionData>(entity) {
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
    world: &mut hecs::World,
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
        world
            .query::<(&FacilityIdentity, &FacilityLocation)>()
            .iter()
            .find(|(_, (_, loc))| loc.location_name == destination)
            .map(|(_, (id, _))| id.body_id.clone())
    };
    let Some(body_id) = body_id else { return };

    let body_center = world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .find(|(_, (id, _))| id.body_id == body_id)
        .map(|(_, (_, orbit))| orbit.universe_position());
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
fn refresh_active_subsidy_counts(world: &mut hecs::World, contracts: &ContractBoard) {
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
    for (_e, data) in world.query_mut::<&mut FactionData>() {
        let n = counts.get(&data.id).copied().unwrap_or(0);
        if data.active_subsidies != n {
            data.active_subsidies = n;
            data.dirty = true;
        }
    }
}
