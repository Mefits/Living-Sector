use crate::builds::{Builds, Faction, HullOrder, Journey, SiteJob, Stage};
use crate::conflict::{Conflict, PIRATE_BASE};
use crate::construction::{
    COMMISSION_FUEL, Construction, MARS_ORE, MARS_SITE, MarsProject, Project, SHIP_METAL, SITE,
    YARD_METAL,
};
use crate::freight::{Assignment, Commodity, Fleet, Leg, Ship, ShipRole};
use crate::governance::{Assessment, Governance};
use crate::industry::{Batch, Deposit, Industry, Operation, Plant};
use crate::legacy_freight::{FreightPhase, Freighter};
use crate::planning::{self, Choice, Kind, Program, Site as BuildSite};
use crate::security::Security;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};

pub const SHIPMENT: u32 = 50;
pub const TANK: u32 = 100;
pub const BELT: &str = "belt-outpost";
pub const EARTH: &str = "earth-station";
pub const SHIP: &str = "Грузовой-001";
const FLIGHT_FUEL: u32 = 8;
const FUEL_SHIPMENT: u32 = 24;
const BELT_CAPACITY: u32 = 100;
pub const METAL_CAPACITY: u32 = 80;
const SEED_ORE: u32 = 500;

fn seed_ore() -> u32 {
    SEED_ORE
}

const QUANTUM: f64 = 0.25;

#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Phase {
    #[default]
    #[serde(alias = "mining")]
    Waiting,
    Loading,
    Relocating,
    Outbound,
    Unloading,
    Returning,
    NoFuelAtBelt,
    NoFuelAtEarth,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Sim {
    #[serde(default, skip_serializing)]
    pub phase: Phase,
    #[serde(default, skip_serializing)]
    pub elapsed: f64,
    pub seconds: f64,
    pub tick: u64,
    #[serde(default)]
    pub fleet: Fleet,
    #[serde(default)]
    pub warehouses: BTreeMap<String, Warehouse>,
    #[serde(default)]
    pub industry: Industry,
    #[serde(default)]
    pub builds: Builds,
    #[serde(default, skip_serializing)]
    belt_ore: u32,
    #[serde(default, skip_serializing)]
    station_ore: u32,
    #[serde(default, skip_serializing)]
    pub cargo: u32,
    #[serde(default, skip_serializing)]
    pub fuel_cargo: u32,
    #[serde(default, skip_serializing)]
    fuel_order: bool,
    #[serde(default, skip_serializing)]
    pub fuel: u32,
    #[serde(default, skip_serializing)]
    belt_fuel: u32,
    #[serde(default, skip_serializing)]
    station_fuel: u32,
    #[serde(default, skip_serializing)]
    metal: u32,
    #[serde(default, skip_serializing)]
    mining_elapsed: f64,
    #[serde(default, skip_serializing)]
    smelting_elapsed: f64,
    #[serde(default)]
    pending: f64,
    #[serde(default)]
    pub governance: Governance,
    #[serde(default)]
    pub construction: Construction,
    #[serde(default, skip_serializing)]
    pub second_freighter: Option<Freighter>,
    #[serde(default = "seed_ore", skip_serializing)]
    deposit: u32,
    #[serde(default)]
    pub conflict: Conflict,
    #[serde(default)]
    pub security: Security,
    #[serde(default, skip_serializing)]
    pub mars_route: bool,
    #[serde(default)]
    pub genesis_program: Program,
    #[serde(default)]
    pub pirate_program: Program,
    #[serde(default)]
    pub outpost_site: Option<BuildSite>,
    #[serde(default, skip_serializing)]
    pub(crate) route_duration: f64,
    #[serde(default, skip_serializing)]
    pub(crate) return_duration: f64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Warehouse {
    #[serde(default)]
    pub owner: Faction,
    pub name: String,
    pub x: f64,
    pub y: f64,
    pub capacity: u32,
    #[serde(default)]
    pub stock: HashMap<Commodity, u32>,
    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub limits: HashMap<Commodity, u32>,
}

#[derive(Clone, Serialize)]
pub struct Event {
    kind: &'static str,
    commodity: &'static str,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub(crate) location: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) faction_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) ship_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) target_id: Option<String>,
    pub(crate) quantity: u32,
    stock: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    ship_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub actor: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    facility: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

impl Default for Sim {
    fn default() -> Self {
        Self {
            phase: Phase::Waiting,
            elapsed: 0.0,
            seconds: 0.0,
            tick: 0,
            fleet: Fleet::default(),
            warehouses: BTreeMap::new(),
            industry: Industry::default(),
            builds: Builds::default(),
            belt_ore: 0,
            station_ore: 0,
            cargo: 0,
            fuel_cargo: 0,
            fuel_order: false,
            fuel: TANK,
            belt_fuel: 200,
            station_fuel: 200,
            metal: 0,
            mining_elapsed: 0.0,
            smelting_elapsed: 0.0,
            pending: 0.0,
            governance: Governance::default(),
            construction: Construction::default(),
            second_freighter: None,
            deposit: SEED_ORE,
            mars_route: false,
            genesis_program: Program::default(),
            pirate_program: Program::default(),
            outpost_site: None,
            route_duration: 0.0,
            return_duration: 0.0,
            security: Security::default(),
            conflict: Conflict {
                pirate_fuel_stock: 18,
                pirate_metal: 24,
                ..Conflict::default()
            },
        }
    }
}

impl Sim {
    pub fn valid(&self) -> bool {
        self.seconds.is_finite()
            && self.seconds >= 0.0
            && (0.0..QUANTUM).contains(&self.pending)
            && self.fleet.valid()
            && self.fleet.ships.values().all(|ship| {
                self.available_location(&ship.location)
                    && ship
                        .leg
                        .as_ref()
                        .is_none_or(|leg| self.available_location(&leg.destination))
                    && ship
                        .task
                        .as_ref()
                        .is_none_or(|task| self.available_location(&task.source))
            })
            && self
                .fleet
                .orders
                .values()
                .all(|order| self.available_location(&order.destination))
            && [EARTH, BELT]
                .iter()
                .all(|id| self.warehouses.contains_key(*id))
            && self.warehouses.values().all(Warehouse::valid)
            && self.industry.valid(self)
            && self.builds.valid(self)
            && self.warehouses.contains_key(PIRATE_BASE)
            && self.fleet.ships.values().all(|ship| {
                ship.sortie
                    .as_ref()
                    .is_none_or(|sortie| self.available_location(&sortie.home))
            })
    }

    pub fn delivery_active(&self) -> bool {
        self.fleet.ships.values().any(|ship| ship.task.is_some())
    }

    pub fn delivery_status(&self) -> &'static str {
        if self.delivery_active() {
            "В работе"
        } else if !self.fleet.orders.is_empty() {
            "Ждёт ресурс, корабль или топливо"
        } else {
            "Нет открытых заказов"
        }
    }

    pub fn station_ore(&self) -> u32 {
        self.stock(EARTH, Commodity::Ore)
    }
    pub fn station_fuel(&self) -> u32 {
        self.stock(EARTH, Commodity::Fuel)
    }
    pub fn belt_ore(&self) -> u32 {
        self.stock(BELT, Commodity::Ore)
    }
    pub fn belt_fuel(&self) -> u32 {
        self.stock(BELT, Commodity::Fuel)
    }
    pub fn metal(&self) -> u32 {
        self.stock(EARTH, Commodity::Metals)
    }
    pub fn deposit(&self) -> u32 {
        self.deposit_remaining(BELT)
    }
    pub fn deposit_remaining(&self, id: &str) -> u32 {
        self.industry
            .deposits
            .get(id)
            .map_or(0, |deposit| deposit.remaining)
    }

    pub fn batch_active(&self) -> bool {
        self.industry
            .plants
            .get(EARTH)
            .is_some_and(|plant| plant.batch.is_some())
    }

    pub fn smelting_status(&self) -> &'static str {
        self.industry
            .plants
            .get(EARTH)
            .map_or("Плавильня отсутствует", |plant| {
                plant.status(self)
            })
    }

    pub fn step(&mut self, delta: f64) -> Vec<Event> {
        self.tick += 1;
        self.pending += delta;
        let mut events = Vec::new();
        while self.pending >= QUANTUM {
            self.pending -= QUANTUM;
            self.seconds += QUANTUM;
            self.plan(&mut events);
            self.plan_storage();
            self.run_facilities(&mut events);
            self.advance_projects(&mut events);
            self.advance_yards(&mut events);
            let mut fleet = std::mem::take(&mut self.fleet);
            fleet.advance(self, &mut events);
            self.fleet = fleet;
            self.construct(&mut events);
            self.run_security(&mut events);
            self.expand(&mut events);
            self.plan_builds(&mut events);
            self.sync_industry();
        }
        events
    }

    fn plan(&mut self, events: &mut Vec<Event>) {
        let fuel = self.station_fuel();
        if let Some(reason) = self.governance.review(fuel, QUANTUM) {
            events.push(decision("policy_changed", "Глава фракции", reason));
        }
        self.plan_fuel();
    }

    fn safety_stock(&self, id: &str, resource: Commodity) -> u32 {
        let owner = self.location_owner(id);
        if resource == Commodity::Fuel && id == self.home_port(owner) {
            self.economic_policy(owner).0
        } else {
            0
        }
    }

    pub fn production_supply(&self, id: &str, resource: Commodity) -> u32 {
        self.stock(id, resource).saturating_sub(
            self.safety_stock(id, resource)
                .saturating_add(self.fleet.reserved(id, resource)),
        )
    }

    pub fn refuel_supply(&self, id: &str) -> u32 {
        self.freight_supply(id, Commodity::Fuel)
    }

    pub fn freight_supply(&self, id: &str, resource: Commodity) -> u32 {
        let local_inputs = self
            .industry
            .plants
            .values()
            .filter(|plant| plant.location == id)
            .filter_map(Plant::recipe)
            .flat_map(|recipe| recipe.inputs)
            .filter(|&&(item, _)| item == resource)
            .map(|&(_, amount)| self.restock_trigger(id, resource, amount))
            .fold(0u32, u32::saturating_add);
        let yard_inputs = self
            .builds
            .yards
            .get(id)
            .and_then(|yard| yard.order.as_ref())
            .filter(|order| order.remaining.is_none())
            .and_then(|order| {
                order
                    .materials()
                    .into_iter()
                    .find(|&(item, _)| item == resource)
            })
            .map_or(0, |(_, amount)| amount);
        self.stock(id, resource).saturating_sub(
            self.safety_stock(id, resource)
                .saturating_add(local_inputs)
                .saturating_add(yard_inputs),
        )
    }

    fn restock_trigger(&self, id: &str, resource: Commodity, batch: u32) -> u32 {
        if id == EARTH && resource == Commodity::Ore {
            self.governance.policy.ore_target().max(batch)
        } else {
            batch.saturating_mul(2)
        }
    }

    pub fn wants_output(&self, id: &str, resource: Commodity) -> bool {
        self.fleet.orders.values().any(|order| {
            order.resource == resource
                && self.location_owner(&order.destination) == self.location_owner(id)
                && order.remaining > self.fleet.incoming(&order.destination, resource)
        })
    }

    pub fn extractable(&self, id: &str, resource: Commodity) -> u32 {
        self.industry
            .plants
            .values()
            .filter(|plant| plant.location == id)
            .filter_map(|plant| {
                let Operation::Extract { deposit, .. } = &plant.operation else {
                    return None;
                };
                let deposit = &self.industry.deposits[deposit];
                if deposit.resource != resource {
                    return None;
                }
                let work = plant.batch.as_ref().map_or(0, |batch| batch.output[0].1);
                Some(deposit.remaining.saturating_add(work))
            })
            .max()
            .unwrap_or(0)
    }

    pub fn locations(&self) -> impl Iterator<Item = &str> {
        self.warehouses
            .keys()
            .map(String::as_str)
            .filter(|id| *id != PIRATE_BASE || self.conflict.base_ready)
    }

    pub fn available_location(&self, id: &str) -> bool {
        matches!(id, SITE | PIRATE_BASE)
            || self.builds.projects.contains_key(id)
            || (id == MARS_SITE && self.construction.mars != MarsProject::Proposed)
            || self.warehouses.contains_key(id)
    }

    pub fn location_owner(&self, id: &str) -> Faction {
        if id == PIRATE_BASE {
            return Faction::Pirates;
        }
        self.warehouses
            .get(id)
            .map(|warehouse| warehouse.owner)
            .or_else(|| self.builds.projects.get(id).map(|job| job.owner))
            .unwrap_or_default()
    }

    pub(crate) fn faction_ready(&self, owner: Faction) -> bool {
        owner != Faction::Pirates || self.conflict.base_progress >= 40.0
    }

    pub(crate) fn legacy_builder_busy(&self, id: &str) -> bool {
        id == "builder-1"
            && (matches!(
                self.construction.phase,
                Project::Hauling | Project::Assembling | Project::Returning
            ) || !matches!(
                self.construction.mars,
                MarsProject::Proposed | MarsProject::Ready
            ))
    }

    pub fn has_build(&self, owner: Faction, kind: Kind) -> bool {
        let legacy = match owner {
            Faction::Genesis => self.genesis_program.has(kind),
            Faction::Pirates => self.pirate_program.has(kind),
            Faction::Independent(_) => false,
        };
        legacy
            || self
                .builds
                .projects
                .values()
                .any(|job| job.owner == owner && job.done && job.choice.kind == kind)
    }

    pub fn travel(&self, from: &str, to: &str) -> (u32, u32) {
        if from == to {
            return (0, 0);
        }
        let (seconds, fuel) = leg(self, from, to);
        ((seconds / QUANTUM) as u32, fuel)
    }

    pub fn stock(&self, id: &str, resource: Commodity) -> u32 {
        self.warehouses
            .get(id)
            .and_then(|warehouse| warehouse.stock.get(&resource))
            .copied()
            .unwrap_or(0)
    }

    pub fn room(&self, id: &str, resource: Commodity) -> u32 {
        self.warehouses
            .get(id)
            .map_or(0, |warehouse| warehouse.room(resource))
    }

    pub fn can_store_after(
        &self,
        id: &str,
        output: &[(Commodity, u32)],
        consumed: &[(Commodity, u32)],
    ) -> bool {
        self.warehouses.get(id).is_some_and(|warehouse| {
            let mut planned = HashMap::<Commodity, u64>::new();
            for &(resource, quantity) in output {
                *planned.entry(resource).or_default() += u64::from(quantity);
            }
            if warehouse.limits.is_empty() {
                let released = consumed
                    .iter()
                    .map(|&(item, amount)| amount.min(warehouse.quantity(item)) as u64)
                    .sum::<u64>();
                planned.values().sum::<u64>()
                    <= u64::from(warehouse.capacity.saturating_sub(warehouse.used())) + released
            } else {
                planned.iter().all(|(&resource, &quantity)| {
                    let released = consumed
                        .iter()
                        .filter(|&&(item, _)| item == resource)
                        .map(|&(_, amount)| amount.min(warehouse.quantity(resource)) as u64)
                        .sum::<u64>();
                    quantity <= u64::from(warehouse.room(resource)) + released
                })
            }
        })
    }

    pub fn withdraw(&mut self, id: &str, resource: Commodity, quantity: u32) -> bool {
        self.warehouses
            .get_mut(id)
            .is_some_and(|warehouse| warehouse.withdraw(resource, quantity))
    }

    pub fn deposit_cargo(&mut self, id: &str, resource: Commodity, quantity: u32) {
        if quantity == 0 {
            return;
        }
        *self
            .warehouses
            .get_mut(id)
            .expect("validated destination")
            .stock
            .entry(resource)
            .or_default() += quantity;
    }

    pub fn freight_event(
        &self,
        action: &str,
        resource: Commodity,
        location: &str,
        quantity: u32,
        ship: &str,
    ) -> Event {
        let mut entry = event(
            match (action, resource) {
                ("loaded", Commodity::Fuel) => "fuel_loaded",
                ("unloaded", Commodity::Fuel) => "fuel_unloaded",
                ("loaded", _) => "cargo_loaded",
                _ => "cargo_unloaded",
            },
            resource.as_str(),
            EARTH,
            quantity,
            self.stock(location, resource),
            None,
        );
        entry.location = location.into();
        entry.faction_id = Some(self.location_owner(location).id().into_owned());
        entry.ship_name = Some(ship.into());
        entry
    }

    fn run_facilities(&mut self, events: &mut Vec<Event>) {
        let ids: Vec<_> = self.industry.plants.keys().cloned().collect();
        for id in ids {
            let location = self.industry.plants[&id].location.clone();
            if !self.faction_ready(self.location_owner(&location)) {
                continue;
            }
            if let Some(batch) = self.industry.plants.get_mut(&id).unwrap().batch.as_mut() {
                batch.remaining = batch.remaining.saturating_sub(1);
                if batch.remaining == 0
                    && self.can_store_after(
                        &location,
                        &self.industry.plants[&id].batch.as_ref().unwrap().output,
                        &[],
                    )
                {
                    let plant = self.industry.plants.get_mut(&id).unwrap();
                    let batch = plant.batch.take().unwrap();
                    let extraction = matches!(plant.operation, Operation::Extract { .. });
                    for (resource, quantity) in batch.output {
                        self.deposit_cargo(&location, resource, quantity);
                        self.fleet.fulfill_local(&location, resource, quantity);
                        let kind = match (extraction, resource) {
                            (true, Commodity::Ore) => "ore_extracted",
                            (true, _) => "resource_extracted",
                            (false, Commodity::Metals) => "metal_smelted",
                            (false, _) => "production_completed",
                        };
                        let mut entry = event(
                            kind,
                            resource.as_str(),
                            &location,
                            quantity,
                            self.stock(&location, resource),
                            None,
                        );
                        entry.faction_id = Some(self.location_owner(&location).id().into_owned());
                        entry.facility = Some(id.clone());
                        events.push(entry);
                    }
                }
                continue;
            }
            if let Some(recipe) = self.industry.plants[&id].recipe() {
                if self.can_store_after(&location, recipe.outputs, recipe.inputs) {
                    for &(resource, amount) in recipe.inputs {
                        let on_hand = self.production_supply(&location, resource);
                        let trigger = self.restock_trigger(&location, resource, amount);
                        if on_hand < trigger {
                            let target = if location
                                == self.home_port(self.location_owner(&location))
                                && resource == Commodity::Ore
                            {
                                SHIPMENT
                            } else {
                                trigger.saturating_mul(2)
                            };
                            let quantity = target
                                .saturating_sub(on_hand)
                                .min(self.room(&location, resource));
                            if quantity > 0 {
                                self.fleet.request(&location, resource, quantity, 10);
                            }
                        }
                    }
                }
            }
            self.start_batch(&id, false);
        }
    }

    fn start_batch(&mut self, id: &str, importing: bool) {
        let plant = &self.industry.plants[id];
        let duration = plant.period;
        let location = plant.location.clone();
        let output = match &plant.operation {
            Operation::Extract { deposit, amount } => {
                if !importing
                    && !self.wants_output(&location, self.industry.deposits[deposit].resource)
                {
                    return;
                }
                let key = deposit.clone();
                let source = &self.industry.deposits[&key];
                let resource = source.resource;
                let quantity = (*amount)
                    .min(source.remaining)
                    .min(self.room(&location, resource));
                if quantity == 0 {
                    return;
                }
                self.industry.deposits.get_mut(&key).unwrap().remaining -= quantity;
                vec![(resource, quantity)]
            }
            Operation::Process { .. } => {
                let recipe = plant.recipe().expect("validated recipe");
                if !importing && !self.can_store_after(&location, recipe.outputs, recipe.inputs) {
                    return;
                }
                if recipe.inputs.iter().any(|&(resource, amount)| {
                    let stock = if importing {
                        self.stock(&location, resource)
                    } else {
                        self.production_supply(&location, resource)
                    };
                    stock < amount
                }) {
                    return;
                }
                for &(resource, amount) in recipe.inputs {
                    assert!(self.withdraw(&location, resource, amount));
                }
                recipe.outputs.to_vec()
            }
        };
        self.industry.plants.get_mut(id).unwrap().batch = Some(Batch {
            remaining: duration,
            duration,
            output,
        });
    }

    pub fn metal_capacity(&self) -> u32 {
        self.warehouses.get(EARTH).map_or(0, |warehouse| {
            warehouse
                .limits
                .get(&Commodity::Metals)
                .copied()
                .unwrap_or(warehouse.capacity)
        })
    }

    pub fn migrate(&mut self) {
        self.migrate_fleet();
        if self.industry.initialized {
            self.migrate_builds();
            self.migrate_security();
            return;
        }
        self.industry.initialized = true;
        self.warehouses.insert(
            EARTH.into(),
            Warehouse::dedicated(
                "Genesis Station",
                [
                    (Commodity::Ore, self.station_ore, 5000),
                    (Commodity::Fuel, self.station_fuel, 200),
                    (
                        Commodity::Metals,
                        self.metal,
                        if self.genesis_program.has(Kind::Warehouse) {
                            140
                        } else {
                            METAL_CAPACITY
                        },
                    ),
                ],
            ),
        );
        self.warehouses.insert(
            BELT.into(),
            Warehouse::dedicated(
                "Добывающая установка",
                [
                    (Commodity::Ore, self.belt_ore, BELT_CAPACITY),
                    (Commodity::Fuel, self.belt_fuel, 200),
                ],
            ),
        );
        self.industry.deposits.insert(
            BELT.into(),
            Deposit {
                resource: Commodity::Ore,
                initial: SEED_ORE,
                remaining: self.deposit,
            },
        );
        self.industry
            .plants
            .insert(BELT.into(), Plant::extract(BELT, 8, 10));
        self.industry
            .plants
            .insert(EARTH.into(), Plant::process(EARTH, 20, "smelt_metals"));
        self.sync_industry();
        if self.mining_elapsed > 0.0 {
            let prefer_mars = self.construction.mars == MarsProject::Ready
                && self.deposit_remaining(MARS_SITE) > 0
                && (self.conflict.lost_ore > 0
                    || self.deposit < SHIPMENT
                    || crate::view::route_distance(self, MARS_SITE, EARTH)
                        < crate::view::route_distance(self, BELT, EARTH));
            self.import_batch(
                if prefer_mars { MARS_SITE } else { BELT },
                self.mining_elapsed,
            );
        }
        if self.smelting_elapsed > 0.0 {
            self.import_batch(EARTH, self.smelting_elapsed);
        }
        self.migrate_builds();
        self.migrate_security();
    }

    fn import_batch(&mut self, id: &str, elapsed: f64) {
        self.start_batch(id, true);
        if let Some(batch) = self
            .industry
            .plants
            .get_mut(id)
            .and_then(|plant| plant.batch.as_mut())
        {
            batch.remaining = batch.duration.saturating_sub((elapsed / QUANTUM) as u32);
        }
    }

    pub(crate) fn import_pirate_stock(&mut self) {
        let war = &self.conflict;
        let slots = Commodity::ALL.iter().map(|&resource| {
            let initial = match resource {
                Commodity::Ore => war.pirate_loot,
                Commodity::Metals => war.pirate_metal,
                Commodity::Fuel => war.pirate_fuel_stock,
                _ => 0,
            };
            (
                resource,
                initial,
                initial.max(match resource {
                    Commodity::Ore if self.pirate_program.has(Kind::Warehouse) => 60,
                    Commodity::Ore => 24,
                    Commodity::Fuel | Commodity::Metals => 200,
                    _ => 24,
                }),
            )
        });
        self.warehouses
            .entry(PIRATE_BASE.into())
            .or_insert_with(|| Warehouse::dedicated_for("Пиратская база", Faction::Pirates, slots));
        if self.pirate_program.has(Kind::Smelter) {
            self.industry
                .plants
                .entry(PIRATE_BASE.into())
                .or_insert_with(|| Plant::process(PIRATE_BASE, 20, "smelt_metals"));
        }
    }

    fn sync_industry(&mut self) {
        if let Some(earth) = self.warehouses.get_mut(EARTH) {
            if self.genesis_program.has(Kind::Warehouse) && !earth.limits.is_empty() {
                earth
                    .limits
                    .entry(Commodity::Metals)
                    .and_modify(|cap| *cap = (*cap).max(140));
            }
        }
        if let Some(plant) = self.industry.plants.get_mut(EARTH) {
            if self.genesis_program.has(Kind::Smelter) {
                plant.period = 14;
            }
        }
        if self.construction.mars == MarsProject::Ready
            && !self.industry.deposits.contains_key(MARS_SITE)
        {
            self.warehouses.entry(MARS_SITE.into()).or_insert_with(|| {
                Warehouse::dedicated(
                    "Рудный аванпост",
                    [(Commodity::Ore, self.construction.mars_ore, SHIPMENT)],
                )
            });
            self.industry.deposits.insert(
                MARS_SITE.into(),
                Deposit {
                    resource: Commodity::Ore,
                    initial: MARS_ORE,
                    remaining: MARS_ORE.saturating_sub(self.construction.mars_extracted),
                },
            );
            self.industry
                .plants
                .insert(MARS_SITE.into(), Plant::extract(MARS_SITE, 8, 10));
        }
    }

    pub fn mars_status(&self) -> &str {
        self.genesis_program
            .decision
            .as_deref()
            .unwrap_or("Администраторы оценивают потребности")
    }

    // Finish any project that was already in transit in a pre-catalogue save.
    fn expand(&mut self, events: &mut Vec<Event>) {
        if matches!(
            self.construction.mars,
            MarsProject::Proposed | MarsProject::Ready
        ) {
            return;
        }
        self.construction.mars_elapsed += QUANTUM;
        if self.construction.mars_elapsed < self.construction.mars_duration {
            return;
        }
        self.construction.mars_elapsed = 0.0;
        self.construction.mars = match self.construction.mars {
            MarsProject::Positioning => {
                self.construction.mars_duration = self.construction.mars_outbound;
                MarsProject::Hauling
            }
            MarsProject::Hauling => {
                self.construction.mars_duration = 16.0;
                MarsProject::Building
            }
            MarsProject::Building => {
                self.construction.mars_duration = self.construction.mars_return;
                events.push(decision(
                    "mars_completed",
                    "Строитель-001",
                    "Рудный аванпост Марса построен.".into(),
                ));
                MarsProject::Returning
            }
            MarsProject::Returning => MarsProject::Ready,
            _ => unreachable!(),
        };
    }

    fn migrate_builds(&mut self) {
        if self.builds.initialized {
            return;
        }
        self.builds.initialized = true;
        let prior_mine = self
            .genesis_program
            .active
            .filter(|work| work.choice.kind == Kind::Mine)
            .map(|work| work.choice.site)
            .or_else(|| {
                (self.construction.mars != MarsProject::Proposed)
                    .then_some(self.outpost_site.unwrap_or(BuildSite::Mars))
            });
        for (id, quantity, site) in [
            ("mars-vein", MARS_ORE, BuildSite::Mars),
            ("belt-vein", 220, BuildSite::Belt),
        ] {
            if prior_mine == Some(site) {
                continue;
            }
            self.industry.deposits.entry(id.into()).or_insert(Deposit {
                resource: Commodity::Ore,
                initial: quantity,
                remaining: quantity,
            });
        }
        for (owner, builder, name) in [
            (Faction::Genesis, "builder-1", "Строитель-001"),
            (Faction::Pirates, "pirate-builder-1", "Пиратский строитель"),
        ] {
            self.fleet.ships.entry(builder.into()).or_insert_with(|| {
                Ship::new(name, owner.legacy_home(), 0, owner, ShipRole::Constructor)
            });
            let program = match owner {
                Faction::Genesis => &mut self.genesis_program,
                Faction::Pirates => &mut self.pirate_program,
                Faction::Independent(_) => continue,
            };
            let yard = program.has(Kind::Yard);
            if let Some(work) = program.active.take() {
                let travel = (work.travel * 4.0).ceil().max(1.0) as u32;
                let (stage, left) = if work.finished_assembly() {
                    (Stage::Returning, work.remaining)
                } else if work.on_site() {
                    (Stage::Assembly, work.remaining - work.travel)
                } else {
                    (
                        Stage::Outbound,
                        work.remaining - work.travel - work.choice.kind.spec().seconds,
                    )
                };
                let id = crate::view::build_id(owner == Faction::Pirates, work.choice);
                self.builds.projects.insert(
                    id,
                    SiteJob {
                        owner,
                        choice: work.choice,
                        done: false,
                        legacy: true,
                        supply_port: None,
                        journey: Some(Journey {
                            builder: builder.into(),
                            stage,
                            left: (left * 4.0).ceil().max(1.0) as u32,
                            travel,
                            return_fuel: work.fuel / 2,
                        }),
                    },
                );
            }
            if yard {
                let id = crate::view::build_id(
                    owner == Faction::Pirates,
                    Choice {
                        kind: Kind::Yard,
                        site: BuildSite::Earth,
                    },
                );
                self.register_yard(&id, owner);
            }
        }
        if self.construction.yard_ready() {
            self.register_yard(SITE, Faction::Genesis);
        }
    }

    fn cargo_demand(&self, owner: Faction, available_only: bool) -> u64 {
        self.fleet
            .orders
            .values()
            .filter(|order| {
                self.location_owner(&order.destination) == owner
                    && !self.builds.yards.contains_key(&order.destination)
                    && (!available_only
                        || self.locations().any(|source| {
                            source != order.destination
                                && self.location_owner(source) == owner
                                && (self.freight_supply(source, order.resource) > 0
                                    || self.extractable(source, order.resource) > 0)
                        })
                        || self.fleet.incoming(&order.destination, order.resource) > 0)
            })
            .map(|order| u64::from(order.remaining))
            .sum()
    }

    fn missing_freighters(&self, owner: Faction, demand: u64) -> u64 {
        let capacity: u64 = self
            .fleet
            .ships
            .values()
            .filter(|ship| ship.owner == owner && ship.role == ShipRole::Freighter)
            .map(|ship| u64::from(ship.capacity))
            .sum();
        let committed = self
            .builds
            .yards
            .iter()
            .filter(|(id, yard)| {
                self.location_owner(id) == owner
                    && yard
                        .order
                        .as_ref()
                        .is_some_and(|order| order.role == ShipRole::Freighter)
            })
            .count() as u64;
        demand
            .saturating_mul(2)
            .saturating_sub(capacity)
            .div_ceil(50)
            .saturating_sub(committed)
    }

    fn assess_faction(&self, owner: Faction) -> Assessment {
        let home = self.home_port(owner);
        let open_cargo = self.cargo_demand(owner, false);
        let transportable_cargo = self.cargo_demand(owner, true);
        let damage = self
            .fleet
            .ships
            .values()
            .filter(|ship| ship.owner == owner)
            .map(|ship| ship.damage)
            .sum();
        let threat = self.alert(owner);
        let military_demand = self.economic_policy(owner).2.is_some_and(|military| {
            !self
                .fleet
                .ships
                .values()
                .any(|ship| ship.owner == owner && ship.role == military)
                && !self.builds.yards.iter().any(|(id, yard)| {
                    self.location_owner(id) == owner
                        && yard
                            .order
                            .as_ref()
                            .is_some_and(|order| order.role == military)
                })
                && !self
                    .security
                    .legacy_orders
                    .iter()
                    .any(|order| order.owner == owner)
                && match military {
                    ShipRole::Patrol => threat,
                    ShipRole::Raider => self.sees_raiding_opportunity(owner),
                    _ => false,
                }
        });
        let reserve = self.safety_stock(home, Commodity::Fuel);
        let fuel = self.stock(home, Commodity::Fuel);
        let missing_freighters = self.missing_freighters(owner, transportable_cargo);
        let storage_blocked = self.industry.plants.values().any(|plant| {
            self.location_owner(&plant.location) == owner
                && plant.recipe().is_some_and(|recipe| {
                    recipe.outputs.iter().any(|&(resource, amount)| {
                        resource == Commodity::Metals
                            && self.room(&plant.location, resource) < amount
                    })
                })
        });
        let mut blockers = self.port_blockers(owner);
        let mut builders = self
            .fleet
            .ships
            .iter()
            .filter(|(_, ship)| ship.owner == owner && ship.role == ShipRole::Constructor)
            .peekable();
        if builders.peek().is_none() {
            blockers.push("Нет строительного корабля".into());
        } else {
            for (_, ship) in builders.filter(|(id, ship)| {
                ship.task.is_none()
                    && ship.leg.is_none()
                    && self.builds.builder_job(id).is_none()
                    && !self.legacy_builder_busy(id)
            }) {
                let fuel_for_project = self.production_supply(&ship.location, Commodity::Fuel);
                if fuel_for_project < crate::builds::SITE_ENERGY
                    || fuel_for_project.saturating_add(ship.fuel) < crate::builds::SITE_ENERGY + 4
                {
                    blockers.push(format!("{} · {} топлива в баке и {} доступно на складе. Местный строительный рейс с монтажом требует минимум 6.", ship.name, ship.fuel, fuel_for_project));
                }
            }
        }
        let priority = if fuel <= reserve + 4 {
            "Сберечь топливо"
        } else if military_demand {
            if owner == Faction::Genesis {
                "Защитить поставки"
            } else {
                "Восстановить рейдовую группу"
            }
        } else if damage >= 18 {
            "Восстановить корпуса"
        } else if missing_freighters > 0 {
            "Увеличить провозную ёмкость"
        } else if open_cargo > 0 && transportable_cargo == 0 {
            "Найти источник ресурсов"
        } else if storage_blocked {
            "Освободить место для выпуска"
        } else {
            "Поддерживать снабжение"
        };
        Assessment {
            open_cargo,
            missing_freighters,
            damage,
            threat,
            military_demand,
            ore_need: self.fleet.orders.values().any(|order| {
                order.resource == Commodity::Ore && self.location_owner(&order.destination) == owner
            }),
            ore_stock: self.stock(home, Commodity::Ore),
            metal_stock: self.stock(home, Commodity::Metals),
            fuel_stock: fuel,
            storage_blocked,
            reserve_fuel: reserve,
            priority: priority.into(),
            blockers,
        }
    }

    fn plan_builds(&mut self, events: &mut Vec<Event>) {
        if !((self.seconds / QUANTUM) as u64).is_multiple_of(16) {
            return;
        }
        for owner in self.economic_owners().collect::<Vec<_>>() {
            if !self.faction_ready(owner) {
                continue;
            }
            let assessment = self.assess_faction(owner);
            if self.governance.assessments.get(&owner).is_none_or(|last| {
                last.priority != assessment.priority || last.blockers != assessment.blockers
            }) {
                events.push(self.record_priority(
                    owner,
                    &assessment.priority,
                    &assessment.blockers,
                ));
            }
            let military = self.economic_policy(owner).2;
            let mut demand = assessment.missing_freighters;
            let mut security = assessment.military_demand;
            let available_yards: Vec<_> = self
                .builds
                .yards
                .iter()
                .filter(|(id, yard)| self.location_owner(id) == owner && yard.order.is_none())
                .map(|(id, _)| id.clone())
                .collect();
            let mut need_builder = self
                .builds
                .projects
                .values()
                .any(|project| project.owner == owner && !project.done)
                && !self
                    .fleet
                    .ships
                    .values()
                    .any(|ship| ship.owner == owner && ship.role == ShipRole::Constructor)
                && !self.builds.yards.iter().any(|(id, yard)| {
                    self.location_owner(id) == owner
                        && yard
                            .order
                            .as_ref()
                            .is_some_and(|order| order.role == ShipRole::Constructor)
                });
            for id in available_yards {
                let role = if security {
                    security = false;
                    military.expect("security demand has a military role")
                } else if need_builder {
                    need_builder = false;
                    ShipRole::Constructor
                } else if demand > 0 {
                    demand -= 1;
                    ShipRole::Freighter
                } else {
                    break;
                };
                self.builds.yards.get_mut(&id).unwrap().order = Some(HullOrder {
                    role,
                    remaining: None,
                });
            }
            let available = self.fleet.ships.iter().filter(|(id, ship)| {
                ship.owner == owner
                    && ship.role == ShipRole::Constructor
                    && ship.task.is_none()
                    && ship.leg.is_none()
                    && self.builds.builder_job(id).is_none()
                    && !self.legacy_builder_busy(id)
            });
            let candidate = available
                .filter_map(|(_, builder)| {
                    planning::choose(
                        self.construction_budget(&builder.location, Commodity::Metals)
                            .min(builder.capacity),
                        self.construction_budget(&builder.location, Commodity::Fuel)
                            .saturating_sub(crate::builds::SITE_ENERGY)
                            .saturating_add(builder.fuel)
                            .min(builder.tank),
                        |kind, site| {
                            self.construction_need(
                                owner,
                                kind,
                                site,
                                &assessment,
                                demand > 0,
                                security,
                            )
                        },
                        |site| crate::view::build_distance(self, &builder.location, site),
                    )
                    .map(|choice| (choice, builder.location.clone()))
                })
                .next();
            if let Some((choice, port)) = candidate {
                let message = format!(
                    "{} · {}. Приоритет: {}.",
                    choice.kind.spec().name,
                    choice.site.label(),
                    assessment.priority
                );
                match owner {
                    Faction::Genesis => self.genesis_program.decision = Some(message),
                    Faction::Pirates => self.pirate_program.decision = Some(message),
                    Faction::Independent(_) => {}
                }
                self.enqueue_project(owner, choice, port);
            }
            self.governance.assessments.insert(owner, assessment);
        }
    }

    fn construction_need(
        &self,
        owner: Faction,
        kind: Kind,
        site: BuildSite,
        state: &Assessment,
        freight: bool,
        security: bool,
    ) -> f64 {
        if self.builds.has_pending(owner, kind) {
            return 0.0;
        }
        let port_has_yard = self
            .builds
            .yards
            .keys()
            .any(|id| self.location_owner(id) == owner);
        let home = self.home_port(owner);
        let fuel_need = state.fuel_stock < self.economic_policy(owner).1;
        let demand_gas = self.fleet.orders.values().any(|order| {
            order.resource == Commodity::Gas && self.location_owner(&order.destination) == owner
        });
        let usable_source = |kind| {
            self.construction_source(site, kind)
                .is_some_and(|id| self.deposit_remaining(id) > 0)
        };
        match kind {
            Kind::Yard if !port_has_yard && security => 42.0,
            Kind::Yard if !port_has_yard && freight => 26.0,
            Kind::Mine
                if state.ore_need
                    && !self.has_producer(owner, Commodity::Ore)
                    && usable_source(Kind::Mine) =>
            {
                31.0
            }
            Kind::Gas
                if demand_gas
                    && !self.has_producer(owner, Commodity::Gas)
                    && usable_source(Kind::Gas) =>
            {
                40.0
            }
            Kind::Refinery
                if fuel_need
                    && !self.has_producer(owner, Commodity::Fuel)
                    && (self.has_producer(owner, Commodity::Gas)
                        || self.deposit_remaining("jupiter-gas") > 0
                        || self.stock(home, Commodity::Gas) >= 6) =>
            {
                36.0
            }
            Kind::Warehouse
                if state.storage_blocked
                    && !self.builds.projects.iter().any(|(id, job)| {
                        job.owner == owner
                            && job.done
                            && job.choice.kind == Kind::Warehouse
                            && self.room(id, Commodity::Metals) >= 8
                    }) =>
            {
                20.0
            }
            Kind::Smelter
                if !self.has_producer(owner, Commodity::Metals)
                    && (state.ore_stock >= 10 || self.has_producer(owner, Commodity::Ore)) =>
            {
                23.0
            }
            Kind::Repair if state.damage >= 18 && !self.has_build(owner, kind) => 24.0,
            Kind::Observation if state.threat && !self.has_build(owner, kind) => 16.0,
            _ => 0.0,
        }
    }

    pub fn migrate_fleet(&mut self) {
        if self.fleet.initialized {
            return;
        }
        self.fleet.initialized = true;
        if !self.fleet.ships.is_empty() {
            return;
        }
        let (active, active_name, parked, parked_name) = if self.construction.active_second {
            ("freighter-2", "Грузовой-002", "freighter-1", SHIP)
        } else {
            ("freighter-1", SHIP, "freighter-2", "Грузовой-002")
        };
        let source = if self.mars_route { MARS_SITE } else { BELT };
        let mut ship = Ship::freighter(active_name, source, self.fuel);
        self.import_legacy_trip(
            &mut ship,
            self.phase,
            self.elapsed,
            source,
            self.cargo,
            self.fuel_cargo,
            self.fuel_order,
            self.route_duration,
            self.return_duration,
        );
        if self.conflict.raid_elapsed > 0.0 && self.phase == Phase::Outbound && self.cargo > 0 {
            self.conflict.raid_target = Some(active.into());
            self.conflict.raid_source = Some(source.into());
            self.conflict.raid_order = ship.task.as_ref().map(|task| task.order.clone());
        }
        self.fleet.ships.insert(active.into(), ship);
        if let Some(legacy) = self.second_freighter.take() {
            let phase = match legacy.phase {
                FreightPhase::Waiting | FreightPhase::NoFuelAtBelt => Phase::Waiting,
                FreightPhase::NoFuelAtEarth => Phase::NoFuelAtEarth,
                FreightPhase::Loading => Phase::Loading,
                FreightPhase::Outbound => Phase::Outbound,
                FreightPhase::Unloading => Phase::Unloading,
                FreightPhase::Returning => Phase::Returning,
            };
            let mut second = Ship::freighter(parked_name, BELT, legacy.fuel);
            self.import_legacy_trip(
                &mut second,
                phase,
                legacy.elapsed,
                BELT,
                legacy.cargo,
                legacy.fuel_cargo,
                legacy.fuel_order,
                legacy.outbound_duration,
                legacy.return_duration,
            );
            self.fleet.ships.insert(parked.into(), second);
        } else if self.construction.phase == Project::Complete {
            self.fleet.ships.insert(
                parked.into(),
                Ship::freighter(parked_name, BELT, self.construction.parked_fuel),
            );
        }
        if self.construction.phase == Project::Complete {
            self.construction.parked_fuel = 0;
        }
    }

    fn import_legacy_trip(
        &mut self,
        ship: &mut Ship,
        phase: Phase,
        elapsed: f64,
        source: &str,
        ore: u32,
        fuel: u32,
        fuel_order: bool,
        outbound: f64,
        returning: f64,
    ) {
        let passed = (elapsed / QUANTUM).floor() as u32;
        let leg = |destination: &str, seconds: f64| {
            let duration = if seconds > 0.0 {
                (seconds / QUANTUM).ceil() as u32
            } else {
                64
            };
            Leg {
                destination: destination.into(),
                duration,
                elapsed: passed.min(duration - 1),
            }
        };
        if matches!(
            phase,
            Phase::Returning | Phase::Unloading | Phase::NoFuelAtEarth
        ) {
            ship.location = EARTH.into();
        }
        ship.leg = match phase {
            Phase::Outbound => Some(leg(EARTH, outbound)),
            Phase::Returning => Some(leg(BELT, returning)),
            Phase::Relocating => {
                ship.location = BELT.into();
                Some(leg(source, outbound))
            }
            _ => None,
        };
        if matches!(
            phase,
            Phase::Loading | Phase::Relocating | Phase::Outbound | Phase::Unloading
        ) {
            let resource = if fuel_order || fuel > 0 {
                Commodity::Fuel
            } else {
                Commodity::Ore
            };
            let cargo = if resource == Commodity::Fuel {
                fuel
            } else {
                ore
            };
            let desired = if resource == Commodity::Fuel {
                FUEL_SHIPMENT
            } else {
                SHIPMENT
            };
            let quantity = if matches!(phase, Phase::Loading | Phase::Relocating) {
                desired
            } else {
                cargo
            };
            if quantity > 0 {
                let already = self.fleet.incoming(EARTH, resource);
                let id = self.fleet.request(EARTH, resource, already + desired, 10);
                let order = self.fleet.orders.get_mut(&id).unwrap();
                order.remaining = order.remaining.max(already + desired);
                ship.task = Some(Assignment {
                    order: id,
                    source: source.into(),
                    quantity,
                    loaded: cargo > 0,
                    handling: if matches!(phase, Phase::Unloading | Phase::Loading) {
                        passed.min(11)
                    } else {
                        0
                    },
                });
            }
        }
    }

    fn construct(&mut self, events: &mut Vec<Event>) {
        match self.construction.phase {
            Project::WaitingMaterials => return,
            Project::WaitingShip => {
                self.construction.parked_fuel = COMMISSION_FUEL;
                self.construction.phase = Project::BuildingShip;
                events.push(decision(
                    "ship_order",
                    "Глава фракции",
                    format!(
                        "Резервный грузовик: выделено {SHIP_METAL} металла из доставленного груза."
                    ),
                ));
                return;
            }
            Project::Complete => return,
            _ => {}
        }
        self.construction.elapsed += QUANTUM;
        if self.construction.elapsed < self.construction.duration() {
            return;
        }
        self.construction.elapsed = 0.0;
        self.construction.phase = match self.construction.phase {
            Project::Hauling => {
                events.push(decision(
                    "yard_assembly",
                    "Строитель-001",
                    format!("Доставил металл на площадку: {YARD_METAL} для верфи и {SHIP_METAL} для корпуса."),
                ));
                Project::Assembling
            }
            Project::Assembling => {
                events.push(decision(
                    "yard_completed",
                    "Строитель-001",
                    "Верфь введена в строй.".into(),
                ));
                Project::Returning
            }
            Project::Returning => Project::WaitingShip,
            Project::BuildingShip => {
                self.construction.parked_fuel -= FLIGHT_FUEL;
                events.push(decision(
                    "ship_completed",
                    "Орбитальная верфь",
                    "Грузовой-002 собран и вылетел к добывающей установке.".into(),
                ));
                Project::TransferringShip
            }
            Project::TransferringShip => {
                self.fleet
                    .ships
                    .entry("freighter-2".into())
                    .or_insert_with(|| {
                        Ship::freighter(
                            "Грузовой-002",
                            BELT,
                            std::mem::take(&mut self.construction.parked_fuel),
                        )
                    });
                events.push(decision(
                    "ship_commissioned",
                    "Снабженец",
                    "Грузовой-002 доступен для рейсов.".into(),
                ));
                Project::Complete
            }
            _ => unreachable!(),
        };
    }
}

pub(crate) fn leg(sim: &Sim, from: &str, to: &str) -> (f64, u32) {
    let distance = crate::view::route_distance(sim, from, to);
    let duration = (distance / 0.46 / QUANTUM).ceil().max(24.0) * QUANTUM;
    (duration, (distance * 1.15).ceil().max(2.0) as u32)
}

pub(crate) fn event(
    kind: &'static str,
    commodity: &'static str,
    location: &str,
    quantity: u32,
    stock: u32,
    ship_name: Option<&'static str>,
) -> Event {
    Event {
        kind,
        commodity,
        location: location.into(),
        faction_id: None,
        ship_id: None,
        target_id: None,
        quantity,
        stock,
        ship_name: ship_name.map(str::to_owned),
        actor: None,
        facility: None,
        reason: None,
    }
}

pub(crate) fn decision(kind: &'static str, actor: &'static str, reason: String) -> Event {
    let mut entry = event(kind, "", "", 0, 0, None);
    entry.actor = Some(actor);
    entry.reason = Some(reason);
    entry
}

pub(crate) fn decision_at(
    kind: &'static str,
    owner: Faction,
    location: &str,
    reason: String,
) -> Event {
    let mut entry = decision(kind, owner.label(), reason);
    entry.location = location.to_owned();
    entry.faction_id = Some(owner.id().into_owned());
    entry
}

impl Warehouse {
    pub(crate) fn shared(name: &str, owner: Faction, capacity: u32) -> Self {
        Self {
            name: name.into(),
            owner,
            capacity,
            x: 0.0,
            y: 0.0,
            stock: HashMap::new(),
            limits: HashMap::new(),
        }
    }

    fn dedicated<const N: usize>(name: &str, slots: [(Commodity, u32, u32); N]) -> Self {
        Self::dedicated_for(name, Faction::Genesis, slots)
    }

    pub(crate) fn dedicated_for(
        name: &str,
        owner: Faction,
        slots: impl IntoIterator<Item = (Commodity, u32, u32)>,
    ) -> Self {
        let (stock, limits) = slots
            .into_iter()
            .map(|(resource, quantity, capacity)| ((resource, quantity), (resource, capacity)))
            .unzip::<_, _, HashMap<_, _>, HashMap<_, _>>();
        Self {
            owner,
            name: name.into(),
            x: 0.0,
            y: 0.0,
            capacity: 0,
            stock: stock
                .into_iter()
                .filter(|&(_, quantity)| quantity > 0)
                .collect(),
            limits,
        }
    }

    fn valid(&self) -> bool {
        self.x.is_finite()
            && self.y.is_finite()
            && if self.limits.is_empty() {
                self.stock
                    .values()
                    .map(|&amount| u64::from(amount))
                    .sum::<u64>()
                    <= u64::from(self.capacity)
            } else {
                self.stock.iter().all(|(&resource, &amount)| {
                    amount <= self.limits.get(&resource).copied().unwrap_or(0)
                })
            }
    }

    pub fn used(&self) -> u32 {
        self.stock.values().copied().fold(0u32, u32::saturating_add)
    }

    pub fn quantity(&self, resource: Commodity) -> u32 {
        self.stock.get(&resource).copied().unwrap_or(0)
    }

    fn room(&self, resource: Commodity) -> u32 {
        if self.limits.is_empty() {
            self.capacity.saturating_sub(self.used())
        } else {
            self.limits
                .get(&resource)
                .copied()
                .unwrap_or(0)
                .saturating_sub(self.quantity(resource))
        }
    }

    fn withdraw(&mut self, resource: Commodity, amount: u32) -> bool {
        self.stock.get_mut(&resource).is_some_and(|stock| {
            if *stock < amount {
                return false;
            }
            *stock -= amount;
            true
        })
    }
}
