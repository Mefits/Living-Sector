use crate::construction::SITE;
use crate::freight::{Commodity, Ship, ShipRole};
use crate::planning::{Choice, Kind, Site};
use crate::sim::{Event, Sim, Warehouse, decision};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, Default, Eq, Ord, PartialEq, PartialOrd, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Faction {
    #[default]
    Genesis,
    Pirates,
}

impl Faction {
    pub fn id(self) -> &'static str {
        match self {
            Self::Genesis => "genesis",
            Self::Pirates => "pirates",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Genesis => "Genesis",
            Self::Pirates => "Пираты",
        }
    }

    pub fn home(self) -> &'static str {
        match self {
            Self::Genesis => crate::sim::EARTH,
            Self::Pirates => crate::conflict::PIRATE_BASE,
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
    pub(crate) fn enqueue_project(&mut self, owner: Faction, choice: Choice) {
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
                        events.push(decision(
                            "building_completed",
                            owner.label(),
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
            if ship.owner != owner
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
        events.push(decision(
            "building_approved",
            owner.label(),
            format!(
                "{} · {}. Погружено {} металла, на рейс выделено {} топлива, на монтаж — {SITE_ENERGY}.",
                id, origin, metal, fuel
            ),
        ));
    }

    fn activate_structure(&mut self, id: &str, owner: Faction, choice: Choice, legacy: bool) {
        if legacy {
            let program = match owner {
                Faction::Genesis => &mut self.genesis_program,
                Faction::Pirates => &mut self.pirate_program,
            };
            program.built.push(choice);
            if choice.kind == Kind::Mine && owner == Faction::Genesis {
                self.construction.mars = crate::construction::MarsProject::Ready;
                self.outpost_site = Some(choice.site);
            }
        }
        match choice.kind {
            Kind::Yard => self.register_yard(id, owner),
            Kind::Warehouse if !legacy => {
                self.warehouses.entry(id.into()).or_insert_with(|| {
                    Warehouse::dedicated_for(
                        choice.kind.spec().name,
                        owner,
                        [(Commodity::Metals, 0, 140), (Commodity::Fuel, 0, 100)],
                    )
                });
            }
            Kind::Smelter if !legacy => {
                self.warehouses.entry(id.into()).or_insert_with(|| {
                    Warehouse::dedicated_for(
                        choice.kind.spec().name,
                        owner,
                        [
                            (Commodity::Ore, 0, 100),
                            (Commodity::Fuel, 0, 80),
                            (Commodity::Metals, 0, 80),
                        ],
                    )
                });
                self.industry.plants.insert(
                    id.into(),
                    crate::industry::Plant::process(id, 14, "smelt_metals"),
                );
            }
            Kind::Mine if !legacy => {
                if let Some(deposit) = self.construction_deposit(choice.site) {
                    self.warehouses.entry(id.into()).or_insert_with(|| {
                        Warehouse::dedicated_for(
                            choice.kind.spec().name,
                            owner,
                            [(Commodity::Ore, 0, 100)],
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
                    ship_id,
                    Ship::new(name.clone(), &id, HULL_FUEL, owner, role),
                );
                self.builds.yards.get_mut(&id).unwrap().order = None;
                events.push(decision(
                    "ship_commissioned",
                    owner.label(),
                    format!("{name} введён в строй на верфи {id}."),
                ));
                continue;
            }
            let metal = match role {
                ShipRole::Freighter => FREIGHTER_METAL,
                ShipRole::Constructor => CONSTRUCTOR_METAL,
                ShipRole::Patrol => 14,
                ShipRole::Raider => 10,
            };
            let mut supplied = true;
            for (resource, amount) in [
                (Commodity::Metals, metal),
                (Commodity::Fuel, HULL_FUEL + HULL_ENERGY),
            ] {
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
                assert!(self.withdraw(&id, Commodity::Metals, metal));
                assert!(self.withdraw(&id, Commodity::Fuel, HULL_FUEL + HULL_ENERGY));
                self.builds
                    .yards
                    .get_mut(&id)
                    .unwrap()
                    .order
                    .as_mut()
                    .unwrap()
                    .remaining = Some(HULL_TIME);
                events.push(decision(
                    "ship_order",
                    owner.label(),
                    format!(
                        "Верфь {id} начала сборку. Списано {metal} металла, {HULL_FUEL} топлива на заправку и {HULL_ENERGY} на сборку."
                    ),
                ));
            }
        }
    }
}
