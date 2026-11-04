use crate::construction::SITE;
use crate::freight::{Commodity, Ship, ShipRole};
use crate::planning::{Choice, Kind, Site};
use crate::sim::{Event, Sim, Warehouse, decision_at};
use serde::{Deserialize, Serialize};
use std::{borrow::Cow, collections::BTreeMap};

#[derive(Clone, Copy, Debug, Default, Eq, Ord, PartialEq, PartialOrd)]
pub enum Faction {
    #[default]
    Genesis,
    Pirates,
    Independent(u16),
}

impl Faction {
    pub fn id(self) -> Cow<'static, str> {
        match self {
            Self::Genesis => Cow::Borrowed("genesis"),
            Self::Pirates => Cow::Borrowed("pirates"),
            Self::Independent(id) => Cow::Owned(format!("faction-{id}")),
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Genesis => "Genesis",
            Self::Pirates => "Пираты",
            Self::Independent(_) => "Независимая фракция",
        }
    }

    pub fn legacy_home(self) -> &'static str {
        match self {
            Self::Genesis => crate::sim::EARTH,
            Self::Pirates => crate::conflict::PIRATE_BASE,
            Self::Independent(_) => "",
        }
    }
}

impl Serialize for Faction {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.id())
    }
}

impl<'de> Deserialize<'de> for Faction {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let id = String::deserialize(deserializer)?;
        match id.as_str() {
            "genesis" => Ok(Self::Genesis),
            "pirates" => Ok(Self::Pirates),
            _ => id
                .strip_prefix("faction-")
                .and_then(|number| number.parse::<u16>().ok())
                .map(Self::Independent)
                .ok_or_else(|| serde::de::Error::custom("invalid faction ID")),
        }
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Builds {
    pub initialized: bool,
    pub next_id: u64,
    pub projects: BTreeMap<String, SiteJob>,
    pub yards: BTreeMap<String, Yard>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SiteJob {
    pub owner: Faction,
    pub choice: Choice,
    #[serde(default)]
    pub done: bool,
    #[serde(default)]
    pub journey: Option<Journey>,
    #[serde(default)]
    pub legacy: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub supply_port: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Journey {
    pub builder: String,
    pub stage: Stage,
    pub left: u32,
    pub travel: u32,
    pub return_fuel: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Stage {
    Outbound,
    Assembly,
    Returning,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Yard {
    #[serde(default)]
    pub order: Option<HullOrder>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HullOrder {
    pub role: ShipRole,
    #[serde(default)]
    pub remaining: Option<u32>,
}

const FREIGHTER_METAL: u32 = 8;
const CONSTRUCTOR_METAL: u32 = 12;
const HULL_FUEL: u32 = 8;
pub(crate) const SITE_ENERGY: u32 = 2;
const HULL_ENERGY: u32 = 2;
const HULL_TIME: u32 = 32;

impl HullOrder {
    pub(crate) fn materials(&self) -> [(Commodity, u32); 2] {
        let metal = match self.role {
            ShipRole::Freighter => FREIGHTER_METAL,
            ShipRole::Constructor => CONSTRUCTOR_METAL,
            ShipRole::Patrol => 14,
            ShipRole::Raider => 10,
        };
        [
            (Commodity::Metals, metal),
            (Commodity::Fuel, HULL_FUEL + HULL_ENERGY),
        ]
    }
}

impl SiteJob {
    pub fn status(&self) -> &'static str {
        match self.journey.as_ref().map(|journey| journey.stage) {
            Some(Stage::Outbound) => "Строитель везёт материалы",
            Some(Stage::Assembly) => "Идёт монтаж",
            Some(Stage::Returning) => "Строитель возвращается",
            None if self.done => "В строю",
            None => "Ждёт строителя, металл или топливо",
        }
    }
}

impl Builds {
    pub fn builder_job(&self, id: &str) -> Option<(&str, &SiteJob, &Journey)> {
        self.projects.iter().find_map(|(target, job)| {
            let trip = job.journey.as_ref()?;
            (trip.builder == id).then_some((target.as_str(), job, trip))
        })
    }

    pub fn has_pending(&self, owner: Faction, kind: Kind) -> bool {
        self.projects
            .values()
            .any(|job| job.owner == owner && !job.done && job.choice.kind == kind)
    }

    pub fn valid(&self, sim: &Sim) -> bool {
        let mut assigned = std::collections::BTreeSet::new();
        self.projects.iter().all(|(id, job)| {
            !matches!(
                id.as_str(),
                crate::sim::EARTH | crate::sim::BELT | crate::conflict::PIRATE_BASE
            ) && job.choice.kind.spec().sites.contains(&job.choice.site)
                && job.supply_port.as_ref().is_none_or(|port| {
                    sim.warehouses.contains_key(port) && sim.location_owner(port) == job.owner
                })
                && job.journey.as_ref().is_none_or(|trip| {
                    trip.left > 0
                        && trip.travel > 0
                        && !job.done
                        && assigned.insert(&trip.builder)
                        && sim.fleet.ships.get(&trip.builder).is_some_and(|ship| {
                            ship.owner == job.owner
                                && ship.role == ShipRole::Constructor
                                && ship.task.is_none()
                                && ship.leg.is_none()
                        })
                })
        }) && self.yards.iter().all(|(id, yard)| {
            sim.warehouses.contains_key(id)
                && yard
                    .order
                    .as_ref()
                    .and_then(|order| order.remaining)
                    .is_none_or(|left| left > 0 && left <= HULL_TIME)
        })
    }
}

impl Sim {
    pub(crate) fn enqueue_project(&mut self, owner: Faction, choice: Choice, supply_port: String) {
        let id = loop {
            self.builds.next_id += 1;
            let id = format!("site-{}", self.builds.next_id);
            if !self.available_location(&id) {
                break id;
            }
        };
        self.builds.projects.insert(
            id,
            SiteJob {
                owner,
                choice,
                done: false,
                journey: None,
                legacy: false,
                supply_port: Some(supply_port),
            },
        );
    }

    pub(crate) fn advance_projects(&mut self, events: &mut Vec<Event>) {
        let ids: Vec<_> = self.builds.projects.keys().cloned().collect();
        for id in ids {
            let job = &mut self.builds.projects.get_mut(&id).unwrap();
            if job.done {
                continue;
            }
            if let Some(trip) = &mut job.journey {
                trip.left -= 1;
                if trip.left != 0 {
                    continue;
                }
                match trip.stage {
                    Stage::Outbound => {
                        trip.stage = Stage::Assembly;
                        trip.left = (job.choice.kind.spec().seconds * 4.0) as u32;
                    }
                    Stage::Assembly => {
                        trip.stage = Stage::Returning;
                        trip.left = trip.travel;
                    }
                    Stage::Returning => {
                        let choice = job.choice;
                        let owner = job.owner;
                        let legacy = job.legacy;
                        job.journey = None;
                        job.done = true;
                        self.activate_structure(&id, owner, choice, legacy);
                        events.push(decision_at(
                            "building_completed",
                            owner,
                            &id,
                            format!(
                                "{} введён в строй · {} · {}.",
                                choice.kind.spec().name,
                                choice.site.label(),
                                id
                            ),
                        ));
                    }
                }
                continue;
            }
            self.assign_builder(&id, events);
        }
    }

    fn assign_builder(&mut self, id: &str, events: &mut Vec<Event>) {
        let job = &self.builds.projects[id];
        let owner = job.owner;
        if !self.faction_ready(owner) {
            return;
        }
        let metal = job.choice.kind.spec().metal;
        let candidate = self.fleet.ships.iter().find_map(|(ship_id, ship)| {
            if job
                .supply_port
                .as_ref()
                .is_some_and(|port| port != &ship.location)
                || ship.owner != owner
                || ship.role != ShipRole::Constructor
                || ship.capacity < metal
                || ship.task.is_some()
                || ship.leg.is_some()
                || self.builds.builder_job(ship_id).is_some()
                || self.legacy_builder_busy(ship_id)
            {
                return None;
            }
            let (travel, one_way) = self.travel(&ship.location, id);
            let fuel = one_way.saturating_mul(2);
            let refill = fuel.saturating_sub(ship.fuel).saturating_add(SITE_ENERGY);
            if fuel > ship.tank
                || self.production_supply(&ship.location, Commodity::Metals) < metal
                || self.production_supply(&ship.location, Commodity::Fuel) < refill
            {
                return None;
            }
            Some((
                ship_id.clone(),
                ship.location.clone(),
                travel.max(1),
                one_way,
                fuel,
                refill,
            ))
        });
        let Some((builder, origin, travel, one_way, fuel, refill)) = candidate else {
            let waiting = self.fleet.ships.iter().find_map(|(ship_id, ship)| {
                if job
                    .supply_port
                    .as_ref()
                    .is_some_and(|port| port != &ship.location)
                    || ship.owner != owner
                    || ship.role != ShipRole::Constructor
                    || ship.capacity < metal
                    || ship.task.is_some()
                    || ship.leg.is_some()
                    || self.builds.builder_job(ship_id).is_some()
                    || self.legacy_builder_busy(ship_id)
                {
                    return None;
                }
                let required = self.travel(&ship.location, id).1.saturating_mul(2);
                let fuel = required.saturating_sub(ship.fuel) + SITE_ENERGY;
                (required <= ship.tank
                    && self.construction_budget(&ship.location, Commodity::Metals) >= metal
                    && self.construction_budget(&ship.location, Commodity::Fuel) >= fuel)
                    .then_some((ship.location.clone(), fuel))
            });
            if let Some((port, fuel)) = waiting {
                self.builds.projects.get_mut(id).unwrap().supply_port = Some(port.clone());
                for (resource, required) in [(Commodity::Metals, metal), (Commodity::Fuel, fuel)] {
                    let deficit = required
                        .saturating_sub(self.production_supply(&port, resource))
                        .min(self.room(&port, resource));
                    if deficit > 0 {
                        self.fleet.request(&port, resource, deficit, 35);
                    }
                }
            }
            return;
        };
        assert!(self.withdraw(&origin, Commodity::Metals, metal));
        if refill > 0 {
            assert!(self.withdraw(&origin, Commodity::Fuel, refill));
        }
        self.fleet.ships.get_mut(&builder).unwrap().fuel += refill - SITE_ENERGY;
        self.fleet.ships.get_mut(&builder).unwrap().fuel -= fuel;
        self.builds.projects.get_mut(id).unwrap().journey = Some(Journey {
            builder,
            stage: Stage::Outbound,
            left: travel,
            travel,
            return_fuel: one_way,
        });
        events.push(decision_at(
            "building_approved",
            owner, id,
            format!(
                "{} · {}. Погружено {} металла, на рейс выделено {} топлива, на монтаж — {SITE_ENERGY}.",
                id, origin, metal, fuel
            ),
        ));
    }

    pub(crate) fn activate_structure(
        &mut self,
        id: &str,
        owner: Faction,
        choice: Choice,
        legacy: bool,
    ) {
        if legacy {
            let program = match owner {
                Faction::Genesis => Some(&mut self.genesis_program),
                Faction::Pirates => Some(&mut self.pirate_program),
                Faction::Independent(_) => None,
            };
            if let Some(program) = program {
                program.built.push(choice);
            }
            if choice.kind == Kind::Mine && owner == Faction::Genesis {
                self.construction.mars = crate::construction::MarsProject::Ready;
                self.outpost_site = Some(choice.site);
            }
        }
        match choice.kind {
            Kind::Yard => self.register_yard(id, owner),
            Kind::Warehouse if !legacy => {
                self.warehouses
                    .entry(id.into())
                    .or_insert_with(|| Warehouse::shared(choice.kind.spec().name, owner, 140));
            }
            Kind::Smelter | Kind::Refinery if !legacy => {
                let (recipe, input, output) = if choice.kind == Kind::Smelter {
                    ("smelt_metals", Commodity::Ore, Commodity::Metals)
                } else {
                    ("crack_fuel", Commodity::Gas, Commodity::Fuel)
                };
                self.warehouses.entry(id.into()).or_insert_with(|| {
                    Warehouse::dedicated_for(
                        choice.kind.spec().name,
                        owner,
                        [(input, 0, 100), (Commodity::Fuel, 0, 80), (output, 0, 80)],
                    )
                });
                self.industry
                    .plants
                    .insert(id.into(), crate::industry::Plant::process(id, 14, recipe));
            }
            Kind::Mine | Kind::Gas if !legacy => {
                if let Some(deposit) = self.construction_source(choice.site, choice.kind) {
                    let resource = self.industry.deposits[deposit].resource;
                    self.warehouses.entry(id.into()).or_insert_with(|| {
                        Warehouse::dedicated_for(
                            choice.kind.spec().name,
                            owner,
                            [(resource, 0, 100)],
                        )
                    });
                    let mut plant = crate::industry::Plant::extract(id, 8, 10);
                    plant.operation = crate::industry::Operation::Extract {
                        deposit: deposit.into(),
                        amount: 10,
                    };
                    self.industry.plants.insert(id.into(), plant);
                }
            }
            _ => {}
        }
    }

    pub(crate) fn register_yard(&mut self, id: &str, owner: Faction) {
        self.warehouses.entry(id.into()).or_insert_with(|| {
            Warehouse::dedicated_for(
                "Орбитальная верфь",
                owner,
                [(Commodity::Metals, 0, 80), (Commodity::Fuel, 0, 100)],
            )
        });
        self.builds.yards.entry(id.into()).or_default();
    }

    pub(crate) fn construction_source(&self, site: Site, kind: Kind) -> Option<&'static str> {
        if kind == Kind::Gas {
            return (site == Site::Jupiter && self.industry.deposits.contains_key("jupiter-gas"))
                .then_some("jupiter-gas");
        }
        if site == Site::Jupiter {
            return self
                .industry
                .deposits
                .contains_key("jupiter-vein")
                .then_some("jupiter-vein");
        }
        self.construction_deposit(site)
            .filter(|deposit| self.industry.deposits.contains_key(*deposit))
    }

    pub(crate) fn construction_deposit(&self, site: Site) -> Option<&'static str> {
        if self
            .industry
            .deposits
            .contains_key(crate::construction::MARS_SITE)
            && self.outpost_site.unwrap_or(Site::Mars) == site
        {
            return Some(crate::construction::MARS_SITE);
        }
        match site {
            Site::Belt => Some("belt-vein"),
            Site::Mars => Some("mars-vein"),
            _ => None,
        }
    }

    pub(crate) fn advance_yards(&mut self, events: &mut Vec<Event>) {
        if self.construction.yard_ready() {
            self.register_yard(SITE, Faction::Genesis);
        }
        let ids: Vec<_> = self.builds.yards.keys().cloned().collect();
        for id in ids {
            let owner = self.location_owner(&id);
            if !self.faction_ready(owner) {
                continue;
            }
            let Some(order) = self.builds.yards[&id].order.as_ref() else {
                continue;
            };
            let role = order.role;
            if let Some(left) = order.remaining {
                if left > 1 {
                    self.builds
                        .yards
                        .get_mut(&id)
                        .unwrap()
                        .order
                        .as_mut()
                        .unwrap()
                        .remaining = Some(left - 1);
                    continue;
                }
                let ship_id = loop {
                    self.builds.next_id += 1;
                    let id = format!("hull-{}", self.builds.next_id);
                    if !self.fleet.ships.contains_key(&id) {
                        break id;
                    }
                };
                let name = format!("{} {}", role.label(), self.builds.next_id);
                self.fleet.ships.insert(
                    ship_id.clone(),
                    Ship::new(name.clone(), &id, HULL_FUEL, owner, role),
                );
                self.builds.yards.get_mut(&id).unwrap().order = None;
                let mut entry = decision_at(
                    "ship_commissioned",
                    owner,
                    &id,
                    format!("{name} введён в строй на верфи {id}."),
                );
                entry.ship_id = Some(ship_id);
                entry.quantity = 1;
                events.push(entry);
                continue;
            }
            let materials = order.materials();
            let mut supplied = true;
            for (resource, amount) in materials {
                let available = self.production_supply(&id, resource);
                if available < amount {
                    supplied = false;
                    let quantity = amount - available;
                    if self.room(&id, resource) >= quantity {
                        self.fleet.request(&id, resource, quantity, 35);
                    }
                }
            }
            if supplied {
                for (resource, amount) in materials {
                    assert!(self.withdraw(&id, resource, amount));
                }
                let metal = materials[0].1;
                self.builds
                    .yards
                    .get_mut(&id)
                    .unwrap()
                    .order
                    .as_mut()
                    .unwrap()
                    .remaining = Some(HULL_TIME);
                events.push(decision_at(
                    "ship_order",
                    owner, &id,
                    format!(
                        "Верфь {id} начала сборку. Списано {metal} металла, {HULL_FUEL} топлива на заправку и {HULL_ENERGY} на сборку."
                    ),
                ));
            }
        }
    }
}
