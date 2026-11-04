use crate::conflict::{
    Conflict, PATROL_DURATION, PATROL_METAL, PATROL_SEED_FUEL, PIRATE_BASE, PIRATE_SEED_METAL,
    Patrol,
};
use crate::construction::{
    COMMISSION_FUEL, Construction, MARS_ORE, MARS_SITE, MarsProject, Project, SHIP_METAL, SITE,
    YARD_METAL,
};
use crate::freight::{Assignment, Commodity, Fleet, Leg, Ship};
use crate::governance::Governance;
use crate::industry::{Batch, Deposit, Industry, Operation, Plant};
use crate::legacy_freight::{FreightPhase, Freighter};
use crate::planning::{self, Kind, Program, Site as BuildSite};
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
    location: String,
    quantity: u32,
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
            self.run_facilities(&mut events);
            let mut fleet = std::mem::take(&mut self.fleet);
            fleet.advance(self, &mut events);
            self.fleet = fleet;
            self.construct(&mut events);
            self.run_conflict(&mut events);
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
        if fuel <= self.governance.leader.reserve() + 16 {
            self.fleet
                .request(EARTH, Commodity::Fuel, FUEL_SHIPMENT, 20);
        }
    }

    fn safety_stock(&self, id: &str, resource: Commodity) -> u32 {
        if id == EARTH && resource == Commodity::Fuel {
            self.governance.leader.reserve()
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
        self.stock(id, resource)
            .saturating_sub(self.safety_stock(id, resource).saturating_add(local_inputs))
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
                && order.destination != id
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
        self.warehouses.keys().map(String::as_str)
    }

    pub fn available_location(&self, id: &str) -> bool {
        id == SITE
            || (id == MARS_SITE && self.construction.mars != MarsProject::Proposed)
            || self.warehouses.contains_key(id)
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
        if quantity > 0 {
            *self
                .warehouses
                .get_mut(id)
                .expect("validated destination")
                .stock
                .entry(resource)
                .or_default() += quantity;
        }
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
        entry.ship_name = Some(ship.into());
        entry
    }

    fn run_facilities(&mut self, events: &mut Vec<Event>) {
        let ids: Vec<_> = self.industry.plants.keys().cloned().collect();
        for id in ids {
            let location = self.industry.plants[&id].location.clone();
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
                        let kind = match (extraction, resource) {
                            (true, Commodity::Ore) => "ore_extracted",
                            (true, _) => "resource_extracted",
                            (false, Commodity::Metals) => "metal_smelted",
                            (false, _) => "production_completed",
                        };
                        let mut entry = event(
                            kind,
                            resource.as_str(),
                            EARTH,
                            quantity,
                            self.stock(&location, resource),
                            None,
                        );
                        entry.location = location.clone();
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
                            let target = if location == EARTH && resource == Commodity::Ore {
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

    fn plan_builds(&mut self, events: &mut Vec<Event>) {
        if let Some(choice) = self.genesis_program.advance(QUANTUM) {
            if choice.kind == Kind::Yard && self.construction.phase == Project::WaitingMaterials {
                self.construction.phase = Project::WaitingShip;
            }
            if choice.kind == Kind::Mine {
                self.construction.mars = MarsProject::Ready;
                self.outpost_site = Some(choice.site);
            }
            events.push(decision(
                "building_completed",
                "Строитель Genesis",
                format!(
                    "{} введён в строй. Площадка: {}.",
                    choice.kind.spec().name,
                    choice.site.label()
                ),
            ));
        }
        if let Some(choice) = self.pirate_program.advance(QUANTUM) {
            events.push(decision(
                "building_completed",
                "Пиратский строитель",
                format!(
                    "{} введён в строй. Площадка: {}.",
                    choice.kind.spec().name,
                    choice.site.label()
                ),
            ));
        }
        if !self.tick.is_multiple_of(4) || self.pending >= QUANTUM {
            return;
        }
        let legacy_mars = self.construction.mars;
        let free = matches!(
            self.construction.phase,
            Project::Complete | Project::WaitingMaterials
        ) && matches!(legacy_mars, MarsProject::Proposed | MarsProject::Ready)
            && !matches!(self.conflict.patrol, Patrol::Delivering | Patrol::Building);
        if free && self.genesis_program.active.is_none() {
            let need = |kind, site| match kind {
                Kind::Yard
                    if site == BuildSite::Earth
                        && self.construction.phase == Project::WaitingMaterials
                        && self.deposit() < SEED_ORE - SHIPMENT
                        && self.station_ore() < 30 =>
                {
                    22.0
                }
                Kind::Mine if legacy_mars == MarsProject::Proposed => {
                    let pressure = self.conflict.lost_ore.min(60) as f64 * 0.8
                        + if self.deposit() < 140 { 26.0 } else { 0.0 };
                    if site == BuildSite::Belt {
                        pressure * 0.6
                    } else {
                        pressure
                    }
                }
                Kind::Warehouse
                    if site == BuildSite::Earth
                        && self.room(EARTH, Commodity::Metals) < 8
                        && self.station_ore() >= 10 =>
                {
                    14.0
                }
                Kind::Smelter
                    if site == BuildSite::Earth
                        && self.station_ore() >= 40
                        && self.room(EARTH, Commodity::Metals) > 16 =>
                {
                    14.0
                }
                Kind::Repair if site == BuildSite::Earth && self.conflict.patrol_damage >= 18 => {
                    20.0
                }
                Kind::Observation
                    if site == BuildSite::Earth && self.conflict.heightened_alert() =>
                {
                    12.0
                }
                _ => 0.0,
            };
            let work = planning::choose(
                &self.genesis_program,
                self.production_supply(EARTH, Commodity::Metals),
                self.production_supply(EARTH, Commodity::Fuel),
                need,
                |site| crate::view::build_distance(self, false, site),
            );
            if let Some(work) = work {
                assert!(self.withdraw(EARTH, Commodity::Metals, work.choice.kind.spec().metal));
                assert!(self.withdraw(EARTH, Commodity::Fuel, work.fuel));
                approve(&mut self.genesis_program, work, "Genesis", events);
            }
        }
        if self.conflict.base_progress >= 40.0 && self.pirate_program.active.is_none() {
            let need = |kind, site| {
                if !matches!(site, BuildSite::Jupiter | BuildSite::Outer) {
                    return 0.0;
                }
                match kind {
                    Kind::Yard if self.conflict.raider_destroyed => 27.0,
                    Kind::Repair if self.conflict.raider_damaged => 18.0,
                    Kind::Observation if self.conflict.intercepted_raids > 0 => 12.0,
                    Kind::Smelter if self.conflict.pirate_loot >= 20 => 15.0,
                    Kind::Warehouse if self.conflict.pirate_loot >= 20 => 14.0,
                    _ => 0.0,
                }
            };
            let work = planning::choose(
                &self.pirate_program,
                self.conflict.pirate_metal,
                self.conflict.pirate_fuel_stock.saturating_sub(2),
                need,
                |site| crate::view::build_distance(self, true, site),
            );
            if let Some(work) = work {
                self.conflict.pirate_metal -= work.choice.kind.spec().metal;
                self.conflict.pirate_fuel_stock -= work.fuel;
                approve(&mut self.pirate_program, work, "Пираты", events);
            }
        }
    }

    fn run_conflict(&mut self, events: &mut Vec<Event>) {
        let threat_seen = self.conflict.lost_ore > 0
            || self.conflict.pirate_loot > 0
            || self.conflict.raider_cargo > 0;
        let target = self.fleet.ships.iter().find_map(|(id, ship)| {
            let task = ship.task.as_ref()?;
            let order = self.fleet.orders.get(&task.order)?;
            let leg = ship.leg.as_ref()?;
            (task.loaded
                && task.quantity >= 10
                && order.resource == Commodity::Ore
                && leg.elapsed == 0)
                .then(|| (id.clone(), ship.location.clone(), task.order.clone()))
        });
        let raid_distance = crate::view::route_distance(
            self,
            PIRATE_BASE,
            target
                .as_ref()
                .map_or(BELT, |(_, source, _)| source.as_str()),
        );
        let raid_cost = (raid_distance * 0.42).ceil().clamp(2.0, 6.0) as u32;
        let free_metal = self.production_supply(EARTH, Commodity::Metals);
        let free_fuel = self.production_supply(EARTH, Commodity::Fuel);
        let earth = self.warehouses.get_mut(EARTH).expect("station inventory");
        let war = &mut self.conflict;
        if war.base_progress < 40.0 {
            war.base_progress += QUANTUM;
            if war.base_progress == 36.0 {
                war.base_ready = true;
                events.push(decision(
                    "pirate_base_built",
                    "Пиратская экспедиция",
                    format!(
                        "Собрала базу из половины стартового груза в {PIRATE_SEED_METAL} металла."
                    ),
                ));
            }
            if war.base_progress == 40.0 {
                war.raider_fuel = 6;
                events.push(decision(
                    "raider_built",
                    "Пиратская экспедиция",
                    "Собрала рейдер из оставшихся 8 металла и заправила его из стартового запаса."
                        .into(),
                ));
            }
        }
        if war.raider_return > 0.0 {
            war.raider_return += QUANTUM;
            if war.raider_return >= war.return_duration() {
                let landed = std::mem::take(&mut war.raider_cargo);
                war.pirate_loot += landed;
                war.raider_return = 0.0;
                if landed > 0 {
                    events.push(event(
                        "raid_delivered",
                        "ore",
                        PIRATE_BASE,
                        landed,
                        war.pirate_loot,
                        None,
                    ));
                }
            }
        }
        if war.base_progress >= 40.0 && war.raider_return == 0.0 && war.raid_elapsed == 0.0 {
            if (war.raider_damaged
                || war.raider_destroyed
                || self.pirate_program.has(Kind::Smelter))
                && war.pirate_metal < if war.raider_destroyed { 8 } else { 2 }
                && war.pirate_loot >= 10
                && war.pirate_fuel_stock >= 1
            {
                war.pirate_loot -= 10;
                war.pirate_fuel_stock -= 1;
                war.pirate_metal += 8;
                events.push(event(
                    "pirate_smelting",
                    "metals",
                    PIRATE_BASE,
                    8,
                    war.pirate_metal,
                    None,
                ));
            }
            if war.raider_destroyed {
                if self.pirate_program.has(Kind::Yard)
                    && war.rebuild_elapsed == 0.0
                    && war.pirate_metal >= 8
                    && war.pirate_fuel_stock >= 2
                {
                    war.pirate_metal -= 8;
                    war.pirate_fuel_stock -= 2;
                    war.rebuild_elapsed = QUANTUM;
                    events.push(decision(
                        "raider_rebuild",
                        "Пираты",
                        "Заложен новый рейдер из 8 металла.".into(),
                    ));
                } else if war.rebuild_elapsed > 0.0 {
                    war.rebuild_elapsed += QUANTUM;
                    if war.rebuild_elapsed >= 16.0 {
                        war.rebuild_elapsed = 0.0;
                        war.raider_damage = 0;
                        war.raider_destroyed = false;
                        war.raider_generation += 1;
                        war.raider_fuel = 2;
                        events.push(decision(
                            "raider_built",
                            "Пираты",
                            "Новый рейдер введён в строй.".into(),
                        ));
                    }
                }
            }
            if war.raider_damaged && !war.raider_destroyed && war.pirate_metal >= 2 {
                war.pirate_metal -= if self.pirate_program.has(Kind::Repair) {
                    1
                } else {
                    2
                };
                war.raider_damaged = false;
                war.raider_damage = 0;
                events.push(decision(
                    "raider_repaired",
                    "Пираты",
                    "Рейдер отремонтирован трофейным металлом.".into(),
                ));
            }
            if !war.raider_destroyed && war.raider_fuel < raid_cost && war.pirate_fuel_stock > 0 {
                let quantity = (6 - war.raider_fuel).min(war.pirate_fuel_stock);
                war.pirate_fuel_stock -= quantity;
                war.raider_fuel += quantity;
                events.push(event(
                    "refueled",
                    "fuel",
                    PIRATE_BASE,
                    quantity,
                    war.pirate_fuel_stock,
                    Some("Пиратский рейдер"),
                ));
            }
            if let Some((id, source, order)) = target
                && war.pirate_loot
                    < if self.pirate_program.has(Kind::Warehouse) {
                        60
                    } else {
                        20
                    }
                && !war.raider_destroyed
                && !war.raider_damaged
                && war.raider_fuel >= raid_cost
            {
                war.raid_target = Some(id);
                war.raid_source = Some(source);
                war.raid_order = Some(order);
                war.raider_fuel -= raid_cost;
                war.raid_approach = (raid_distance / 1.2).clamp(5.0, 13.0);
                war.raid_return_time = war.raid_approach * 1.3;
                war.raid_elapsed = QUANTUM;
                war.contact = 0.0;
            }
        }
        if war.raid_elapsed > 0.0 {
            war.raid_elapsed += QUANTUM;
            let approach = war.approach_duration();
            if war.raid_elapsed
                >= approach
                    * if self.genesis_program.has(Kind::Observation) {
                        0.35
                    } else if self.pirate_program.has(Kind::Observation) {
                        0.57
                    } else {
                        0.48
                    }
                && war.near_intercept()
                && war.patrol == Patrol::Ready
            {
                war.contact += QUANTUM;
                if war.contact >= 0.75 && ((war.contact / QUANTUM) as u32).is_multiple_of(3) {
                    war.raider_damage += 32;
                    war.patrol_damage += 9;
                    events.push(decision(
                        "combat_hit",
                        "Патруль-001",
                        "Огонь в секторе: рейдер потерял 32 прочности, патруль — 9.".into(),
                    ));
                }
            }
            if war.raider_damage >= 60 {
                war.raider_destroyed = true;
                war.raider_damaged = false;
                war.raider_fuel = 0;
                war.raid_elapsed = 0.0;
                war.intercepted_raids += 1;
                events.push(decision(
                    "raider_destroyed",
                    "Патруль-001",
                    "Рейдер уничтожен до захвата груза.".into(),
                ));
            } else if war.patrol_damage >= 100 && war.patrol == Patrol::Ready {
                war.patrol = Patrol::Destroyed;
                war.patrol_cycle = 0.0;
                war.patrol_fuel = 0;
                events.push(decision(
                    "patrol_destroyed",
                    "Пираты",
                    "Патрульный корабль уничтожен.".into(),
                ));
            } else if war.raid_elapsed >= approach {
                war.retreat_from = 1.0;
                war.raid_elapsed = 0.0;
                war.raider_return = QUANTUM;
                if war.raider_damage > 0 {
                    war.raider_damaged = true;
                    war.intercepted_raids += 1;
                    events.push(decision(
                        "raid_deflected",
                        "Патруль-001",
                        "Повреждённый рейдер прервал налёт и ушёл.".into(),
                    ));
                    return;
                }
                if let Some(task) = war
                    .raid_target
                    .as_ref()
                    .and_then(|id| self.fleet.ships.get_mut(id))
                    .filter(|ship| ship.leg.is_some())
                    .and_then(|ship| ship.task.as_mut())
                    .filter(|task| {
                        task.loaded
                            && task.quantity >= 10
                            && war.raid_order.as_ref() == Some(&task.order)
                    })
                {
                    task.quantity -= 10;
                    war.raider_cargo = 10;
                    war.lost_ore += 10;
                    events.push(event(
                        "raid_stolen",
                        "ore",
                        PIRATE_BASE,
                        10,
                        war.raider_cargo,
                        None,
                    ));
                    events.push(decision(
                        "patrol_missed",
                        "Служба охраны",
                        if war.patrol_cycle > 0.0 {
                            "Патруль не успел войти в зону перехвата."
                        } else {
                            "На маршруте не было патруля."
                        }
                        .into(),
                    ));
                }
            }
        }
        match war.patrol {
            Patrol::None
                if threat_seen
                    && self.genesis_program.active.is_none()
                    && matches!(
                        self.construction.mars,
                        MarsProject::Proposed | MarsProject::Ready
                    )
                    && self.construction.phase == Project::Complete
                    && free_metal >= PATROL_METAL =>
            {
                assert!(earth.withdraw(Commodity::Metals, PATROL_METAL));
                war.patrol = Patrol::Delivering;
                events.push(decision(
                    "patrol_order",
                    "Глава фракции",
                    format!("После потери груза выделено {PATROL_METAL} металла на самостоятельный патруль."),
                ));
            }
            Patrol::Delivering | Patrol::Building => {
                war.patrol_elapsed += QUANTUM;
                if war.patrol == Patrol::Delivering && war.patrol_elapsed >= 4.0 {
                    war.patrol_elapsed = 0.0;
                    war.patrol = Patrol::Building;
                    events.push(decision(
                        "patrol_inputs",
                        "Строитель-001",
                        "Материалы патруля доставлены на верфь.".into(),
                    ));
                } else if war.patrol == Patrol::Building && war.patrol_elapsed >= 8.0 {
                    war.patrol_elapsed = 0.0;
                    war.patrol = Patrol::Ready;
                    war.patrol_fuel = PATROL_SEED_FUEL;
                    events.push(decision(
                        "patrol_ready",
                        "Орбитальная верфь",
                        "Патруль-001 готов к обходу сектора.".into(),
                    ));
                }
            }
            Patrol::Destroyed
                if free_metal >= PATROL_METAL && free_fuel >= PATROL_SEED_FUEL + 1 =>
            {
                assert!(earth.withdraw(Commodity::Metals, PATROL_METAL));
                assert!(earth.withdraw(Commodity::Fuel, PATROL_SEED_FUEL));
                war.patrol = Patrol::Rebuilding;
                war.patrol_elapsed = 0.0;
                events.push(decision(
                    "patrol_rebuild",
                    "Глава фракции",
                    "Выделены металл и топливо на замену патрульного корабля.".into(),
                ));
            }
            Patrol::Rebuilding => {
                war.patrol_elapsed += QUANTUM;
                if war.patrol_elapsed >= 16.0 {
                    war.patrol_generation += 1;
                    war.patrol_elapsed = 0.0;
                    war.patrol_damage = 0;
                    war.patrol_fuel = PATROL_SEED_FUEL;
                    war.patrol = Patrol::Ready;
                    events.push(decision(
                        "patrol_ready",
                        "Верфь",
                        "Новый патрульный корабль введён в строй.".into(),
                    ));
                }
            }
            Patrol::Ready => {
                if war.patrol_cycle > 0.0 {
                    war.patrol_cycle += QUANTUM;
                    if war.patrol_cycle >= PATROL_DURATION {
                        war.patrol_cycle = 0.0;
                        war.patrol_cooldown = if war.heightened_alert() { 5.0 } else { 14.0 };
                    }
                } else if war.patrol_cooldown > 0.0 {
                    war.patrol_cooldown = (war.patrol_cooldown - QUANTUM).max(0.0);
                } else {
                    if war.patrol_fuel < 2 {
                        let quantity = (PATROL_SEED_FUEL - war.patrol_fuel).min(free_fuel);
                        if quantity > 0 {
                            assert!(earth.withdraw(Commodity::Fuel, quantity));
                            war.patrol_fuel += quantity;
                            events.push(event(
                                "refueled",
                                "fuel",
                                EARTH,
                                quantity,
                                earth.quantity(Commodity::Fuel),
                                Some("Патруль-001"),
                            ));
                        }
                    }
                    let maintenance =
                        war.patrol_sorties > 0 && war.patrol_sorties.is_multiple_of(2);
                    if war.patrol_fuel >= 2 && (!maintenance || free_metal >= 4) {
                        if maintenance {
                            assert!(earth.withdraw(Commodity::Metals, 4));
                            events.push(event(
                                "patrol_maintenance",
                                "metals",
                                EARTH,
                                4,
                                earth.quantity(Commodity::Metals),
                                Some("Патруль-001"),
                            ));
                        }
                        war.patrol_fuel -= 2;
                        war.patrol_cycle = QUANTUM;
                        war.patrol_sorties += 1;
                    }
                }
            }
            _ => {}
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

fn approve(
    program: &mut Program,
    work: planning::Work,
    faction: &'static str,
    events: &mut Vec<Event>,
) {
    let spec = work.choice.kind.spec();
    let reason = match work.choice.kind {
        Kind::Mine => "риск поставок или истощение действующей залежи",
        Kind::Warehouse => "не хватает складской ёмкости",
        Kind::Smelter => "накапливается необработанная руда",
        Kind::Repair => "повреждения кораблей",
        Kind::Observation => "потери на маршруте или сорванные налёты",
        Kind::Yard if faction == "Пираты" => "нужна замена потерянному корпусу",
        Kind::Yard => "снабжению нужен резервный грузовик",
        _ => unreachable!(),
    };
    let message = format!(
        "{} · {} · {}. Выделено {} металла и {} топлива.",
        spec.name,
        work.choice.site.label(),
        reason,
        spec.metal,
        work.fuel
    );
    program.decision = Some(message.clone());
    program.active = Some(work);
    events.push(decision("building_approved", faction, message));
}

pub(crate) fn leg(sim: &Sim, from: &str, to: &str) -> (f64, u32) {
    let distance = crate::view::route_distance(sim, from, to);
    let duration = (distance / 0.46 / QUANTUM).ceil().max(24.0) * QUANTUM;
    (duration, (distance * 1.15).ceil().max(2.0) as u32)
}

pub(crate) fn event(
    kind: &'static str,
    commodity: &'static str,
    location: &'static str,
    quantity: u32,
    stock: u32,
    ship_name: Option<&'static str>,
) -> Event {
    Event {
        kind,
        commodity,
        location: location.into(),
        quantity,
        stock,
        ship_name: ship_name.map(str::to_owned),
        actor: None,
        facility: None,
        reason: None,
    }
}

fn decision(kind: &'static str, actor: &'static str, reason: String) -> Event {
    let mut entry = event(kind, "ore", EARTH, 0, 0, None);
    entry.actor = Some(actor);
    entry.reason = Some(reason);
    entry
}

impl Warehouse {
    fn dedicated<const N: usize>(name: &str, slots: [(Commodity, u32, u32); N]) -> Self {
        Self {
            name: name.into(),
            x: 0.0,
            y: 0.0,
            capacity: 0,
            stock: slots
                .iter()
                .map(|&(item, quantity, _)| (item, quantity))
                .collect(),
            limits: slots
                .into_iter()
                .map(|(item, _, capacity)| (item, capacity))
                .collect(),
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
