use crate::builds::Faction;
use crate::conflict::{PIRATE_BASE, Patrol};
use crate::freight::{Commodity, Ship, ShipRole};
use crate::planning::Kind;
use crate::sim::{EARTH, Event, Sim, decision, event};
use crate::view::{location_point, vessel_point};
use serde::{Deserialize, Serialize};
use sim_core::agents::faction_relations::TreatyKind;
use std::collections::BTreeMap;

const STEP: f64 = 0.25;
const BOARDING_RANGE: f64 = 0.42;
const ALERT_SECONDS: f64 = 150.0;

fn is_zero(value: &f64) -> bool {
    *value == 0.0
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Security {
    pub initialized: bool,
    pub treaty: TreatyKind,
    pub intel: BTreeMap<Faction, Intel>,
    pub legacy_orders: Vec<LegacyHull>,
}

impl Default for Security {
    fn default() -> Self {
        Self {
            initialized: false,
            treaty: TreatyKind::Hostile,
            intel: BTreeMap::new(),
            legacy_orders: Vec::new(),
        }
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Intel {
    pub casualties: u32,
    pub attacks_suffered: u32,
    pub loot_lost: u32,
    pub loot_taken: u32,
    pub last_threat: Option<f64>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LegacyHull {
    pub role: ShipRole,
    pub owner: Faction,
    pub id: String,
    pub fuel: u32,
    pub remaining: u32,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}

impl Point {
    fn distance(self, other: Self) -> f64 {
        (self.x - other.x).hypot(self.y - other.y)
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Sortie {
    pub point: Point,
    pub home: String,
    pub duty: Duty,
    pub left: u32,
    pub fuel_fraction: f64,
    #[serde(default, skip_serializing_if = "is_zero")]
    pub prepaid_fuel: f64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "kind", content = "destination", rename_all = "snake_case")]
pub enum Duty {
    Patrol(String),
    Raid(String),
    Return,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub struct Spoils {
    pub resource: Commodity,
    pub quantity: u32,
}

#[derive(Clone, Copy)]
pub struct Loadout {
    pub hull: u32,
    pub speed: f64,
    pub fuel_rate: f64,
    pub sensor: f64,
    pub range: f64,
    pub damage: u32,
    pub cooldown: u32,
}

impl ShipRole {
    pub fn loadout(self) -> Loadout {
        match self {
            Self::Patrol => Loadout {
                hull: 100,
                speed: 1.0,
                fuel_rate: 1.05,
                sensor: 4.4,
                range: 1.15,
                damage: 18,
                cooldown: 4,
            },
            Self::Raider => Loadout {
                hull: 64,
                speed: 1.22,
                fuel_rate: 0.64,
                sensor: 16.0,
                range: 0.90,
                damage: 10,
                cooldown: 4,
            },
            Self::Freighter => Loadout {
                hull: 72,
                speed: 0.0,
                fuel_rate: 0.0,
                sensor: 0.0,
                range: 0.0,
                damage: 0,
                cooldown: 0,
            },
            Self::Constructor => Loadout {
                hull: 80,
                speed: 0.0,
                fuel_rate: 0.0,
                sensor: 0.0,
                range: 0.0,
                damage: 0,
                cooldown: 0,
            },
        }
    }
}

#[derive(Clone)]
struct Contact {
    id: String,
    owner: Faction,
    point: Point,
    armed: bool,
    flying: bool,
    cargo: Option<Spoils>,
    lane: Option<String>,
    eta: f64,
    arrival: Option<Point>,
}

impl Contact {
    fn intercept(&self, from: Point, speed: f64) -> Option<Point> {
        let arrival = self.arrival?;
        if self.eta <= 0.0 {
            return None;
        }
        let vx = (arrival.x - self.point.x) / self.eta;
        let vy = (arrival.y - self.point.y) / self.eta;
        let dx = self.point.x - from.x;
        let dy = self.point.y - from.y;
        let distance_squared = dx * dx + dy * dy;
        if distance_squared < 0.0001 {
            return Some(self.point);
        }
        let speed_delta = vx * vx + vy * vy - speed * speed;
        let heading = 2.0 * (dx * vx + dy * vy);
        let discriminant = heading * heading - 4.0 * speed_delta * distance_squared;
        if discriminant < 0.0 {
            return None;
        }
        let denominator = discriminant.sqrt() - heading;
        if denominator <= 0.0 {
            return None;
        }
        let time = 2.0 * distance_squared / denominator;
        (time <= self.eta).then_some(Point {
            x: self.point.x + vx * time,
            y: self.point.y + vy * time,
        })
    }
}

impl Sim {
    pub(crate) fn alert(&self, owner: Faction) -> bool {
        self.security
            .intel
            .get(&owner)
            .and_then(|intel| intel.last_threat)
            .is_some_and(|last| self.seconds - last <= ALERT_SECONDS)
    }

    fn hostile(&self, a: Faction, b: Faction) -> bool {
        a != b && matches!(self.security.treaty, TreatyKind::Hostile | TreatyKind::War)
    }

    fn contacts(&self) -> Vec<Contact> {
        self.fleet
            .ships
            .iter()
            .map(|(id, ship)| {
                let cargo = ship
                    .task
                    .as_ref()
                    .filter(|task| task.loaded && task.quantity > 0)
                    .and_then(|task| {
                        self.fleet.orders.get(&task.order).map(|order| Spoils {
                            resource: order.resource,
                            quantity: task.quantity,
                        })
                    });
                Contact {
                    id: id.clone(),
                    owner: ship.owner,
                    point: vessel_point(self, ship),
                    armed: ship.role.is_combat(),
                    flying: ship.sortie.is_some() || ship.leg.is_some(),
                    cargo,
                    lane: ship.leg.as_ref().map(|leg| {
                        if ship.location == ship.owner.home() {
                            leg.destination.clone()
                        } else {
                            ship.location.clone()
                        }
                    }),
                    arrival: ship
                        .leg
                        .as_ref()
                        .map(|leg| location_point(self, &leg.destination)),
                    eta: ship
                        .leg
                        .as_ref()
                        .map_or(0.0, |leg| f64::from(leg.duration - leg.elapsed) * STEP),
                }
            })
            .collect()
    }

    fn sensor_range(&self, owner: Faction, role: ShipRole) -> f64 {
        role.loadout().sensor
            + if self.has_build(owner, Kind::Observation) {
                1.4
            } else {
                0.0
            }
    }

    pub(crate) fn sees_raiding_opportunity(&self, owner: Faction) -> bool {
        let home = location_point(self, owner.home());
        self.contacts().iter().any(|target| {
            self.hostile(owner, target.owner)
                && target.flying
                && target.cargo.is_some_and(|cargo| cargo.quantity >= 5)
                && home.distance(target.point) <= self.sensor_range(owner, ShipRole::Raider)
        })
    }

    pub(crate) fn run_security(&mut self, events: &mut Vec<Event>) {
        self.advance_expedition(events);
        self.service_ships(events);
        let contacts = self.contacts();
        let ids: Vec<_> = self
            .fleet
            .ships
            .iter()
            .filter(|(_, ship)| ship.role.is_combat() && ship.leg.is_none())
            .map(|(id, _)| id.clone())
            .collect();
        for id in ids {
            let mut ship = self.fleet.ships.remove(&id).unwrap();
            self.advance_sortie(&mut ship, &contacts, events);
            self.fleet.ships.insert(id, ship);
        }
        let contacts = self.contacts();
        self.exchange_fire(&contacts, events);
        self.capture_cargo(&contacts, events);
    }

    fn advance_expedition(&mut self, events: &mut Vec<Event>) {
        if self.conflict.base_progress < 40.0 {
            self.conflict.base_progress += STEP;
            if self.conflict.base_progress >= 36.0 && !self.conflict.base_ready {
                self.conflict.base_ready = true;
                events.push(decision(
                    "pirate_base_built",
                    "Пираты",
                    "Экспедиция развернула стартовую базу.".into(),
                ));
            }
            if self.conflict.base_progress >= 40.0 {
                self.fleet
                    .ships
                    .entry("raider-1".into())
                    .or_insert_with(|| {
                        Ship::new(
                            "Рейдер экспедиции",
                            PIRATE_BASE,
                            6,
                            Faction::Pirates,
                            ShipRole::Raider,
                        )
                    });
                events.push(decision(
                    "raider_built",
                    "Пираты",
                    "В строй введён корпус из стартового комплекта экспедиции.".into(),
                ));
            }
        }
        for order in &mut self.security.legacy_orders {
            order.remaining = order.remaining.saturating_sub(1);
        }
        let finished: Vec<_> = self
            .security
            .legacy_orders
            .extract_if(.., |order| order.remaining == 0)
            .collect();
        for order in finished {
            let ship = Ship::new(
                order.role.label(),
                order.owner.home(),
                order.fuel,
                order.owner,
                order.role,
            );
            self.fleet.ships.entry(order.id).or_insert(ship);
            events.push(decision(
                "ship_commissioned",
                order.owner.label(),
                "Ранее оплаченный боевой корпус введён в строй.".into(),
            ));
        }
    }

    fn service_ships(&mut self, events: &mut Vec<Event>) {
        let ids: Vec<_> = self.fleet.ships.keys().cloned().collect();
        let repair_now = ((self.seconds / STEP) as u64).is_multiple_of(16);
        for id in ids {
            let ship = &mut self.fleet.ships.get_mut(&id).unwrap();
            ship.weapon_wait = ship.weapon_wait.saturating_sub(1);
            ship.duty_wait = ship.duty_wait.saturating_sub(1);
            if ship.leg.is_some() || ship.sortie.is_some() || self.builds.builder_job(&id).is_some()
            {
                continue;
            }
            let location = ship.location.clone();
            if let Some(spoils) = ship.spoils {
                let quantity = spoils.quantity.min(self.room(&location, spoils.resource));
                if quantity > 0 {
                    self.deposit_cargo(&location, spoils.resource, quantity);
                    let mut entry = event(
                        "raid_delivered",
                        spoils.resource.as_str(),
                        PIRATE_BASE,
                        quantity,
                        self.stock(&location, spoils.resource),
                        None,
                    );
                    entry.location = location.clone();
                    events.push(entry);
                    let remainder = spoils.quantity - quantity;
                    self.fleet.ships.get_mut(&id).unwrap().spoils =
                        (remainder > 0).then_some(Spoils {
                            quantity: remainder,
                            ..spoils
                        });
                }
            }
            let ship = &self.fleet.ships[&id];
            if !repair_now || ship.damage == 0 {
                continue;
            }
            let near_dock = self.builds.projects.iter().any(|(site, job)| {
                job.owner == ship.owner
                    && job.done
                    && job.choice.kind == Kind::Repair
                    && location_point(self, site).distance(location_point(self, &location)) <= 0.85
            });
            let repair = if near_dock { 22 } else { 12 };
            if self.production_supply(&location, Commodity::Metals) > 0
                && self.production_supply(&location, Commodity::Fuel) > 0
            {
                assert!(self.withdraw(&location, Commodity::Metals, 1));
                assert!(self.withdraw(&location, Commodity::Fuel, 1));
                let ship = self.fleet.ships.get_mut(&id).unwrap();
                let amount = ship.damage.min(repair);
                ship.damage -= amount;
                events.push(decision(
                    "ship_repaired",
                    ship.owner.label(),
                    format!("{} восстановил {amount} корпуса в {}.", ship.name, location),
                ));
            }
        }
    }

    fn advance_sortie(&mut self, ship: &mut Ship, contacts: &[Contact], events: &mut Vec<Event>) {
        let Some(mut flight) = ship.sortie.take() else {
            self.launch_sortie(ship, contacts, events);
            return;
        };
        let profile = ship.role.loadout();
        let home = location_point(self, &flight.home);
        let reserve = (flight.point.distance(home) * profile.fuel_rate).ceil() + 1.0;
        let fuel = f64::from(ship.fuel) + flight.prepaid_fuel - flight.fuel_fraction;
        if fuel <= reserve || flight.left == 0 || ship.damage * 3 >= profile.hull * 2 {
            if matches!(flight.duty, Duty::Raid(_))
                && ship.owner == Faction::Pirates
                && ship.damage * 3 >= profile.hull * 2
            {
                self.conflict.intercepted_raids += 1;
            }
            flight.duty = Duty::Return;
        }
        flight.left = flight.left.saturating_sub(1);
        let destination = match &flight.duty {
            Duty::Return => {
                ship.status = "Возвращается на базу".into();
                home
            }
            Duty::Patrol(anchor) => {
                if let Some(enemy) = contacts
                    .iter()
                    .filter(|enemy| {
                        enemy.armed
                            && enemy.flying
                            && self.hostile(ship.owner, enemy.owner)
                            && flight.point.distance(enemy.point)
                                <= self.sensor_range(ship.owner, ship.role)
                    })
                    .min_by(|a, b| {
                        flight
                            .point
                            .distance(a.point)
                            .total_cmp(&flight.point.distance(b.point))
                    })
                {
                    ship.status = "Идёт на перехват".into();
                    enemy.point
                } else {
                    ship.status = "Патрулирует маршрут".into();
                    let anchor = location_point(self, anchor);
                    Point {
                        x: home.x + (anchor.x - home.x) * 0.65,
                        y: home.y + (anchor.y - home.y) * 0.65,
                    }
                }
            }
            Duty::Raid(id) => {
                if let Some(target) = contacts.iter().find(|target| {
                    &target.id == id
                        && target.flying
                        && target.cargo.is_some()
                        && flight.point.distance(target.point)
                            <= self.sensor_range(ship.owner, ship.role)
                        && self.hostile(ship.owner, target.owner)
                }) {
                    ship.status = "Сближается с грузовым рейсом".into();
                    target
                        .intercept(flight.point, profile.speed)
                        .unwrap_or(target.point)
                } else {
                    flight.duty = Duty::Return;
                    ship.status = "Цель ушла. Возвращается на базу".into();
                    home
                }
            }
        };
        let distance = flight.point.distance(destination);
        let reach = fuel.max(0.0) / profile.fuel_rate;
        let moved = distance.min(reach).min(profile.speed * STEP);
        if moved > 0.0 {
            let progress = moved / distance;
            flight.point.x += (destination.x - flight.point.x) * progress;
            flight.point.y += (destination.y - flight.point.y) * progress;
            let cost = moved * profile.fuel_rate;
            let paid = flight.prepaid_fuel.min(cost);
            flight.prepaid_fuel -= paid;
            flight.fuel_fraction += cost - paid;
            let used = flight.fuel_fraction.floor() as u32;
            ship.fuel -= used.min(ship.fuel);
            flight.fuel_fraction -= f64::from(used);
        }
        if matches!(flight.duty, Duty::Return) && flight.point.distance(home) <= 0.12 {
            ship.location = flight.home;
            ship.fuel = ship
                .fuel
                .saturating_sub(u32::from(flight.fuel_fraction > 0.0));
            ship.duty_wait = if ship.role == ShipRole::Raider {
                20
            } else {
                36
            };
            ship.status = "У причала".into();
        } else {
            if reach <= 0.000_01 {
                ship.status = "В дрейфе. Нет топлива".into();
            }
            ship.sortie = Some(flight);
        }
    }

    fn launch_sortie(&mut self, ship: &mut Ship, contacts: &[Contact], events: &mut Vec<Event>) {
        if ship.duty_wait > 0 || !self.faction_ready(ship.owner) {
            return;
        }
        if ship.damage * 3 >= ship.role.loadout().hull || ship.spoils.is_some() {
            ship.status = if ship.spoils.is_some() {
                "Ждёт место для трофеев"
            } else {
                "Ждёт ремонта"
            }
            .into();
            return;
        }
        let point = location_point(self, &ship.location);
        let home = ship.owner.home();
        let profile = ship.role.loadout();
        let available = ship
            .fuel
            .saturating_add(self.production_supply(&ship.location, Commodity::Fuel))
            .min(ship.tank);
        let (duty, fuel, left) = if ship.location != home {
            let fuel =
                (point.distance(location_point(self, home)) * profile.fuel_rate).ceil() as u32 + 2;
            (Duty::Return, fuel, 120)
        } else if ship.role == ShipRole::Raider {
            let target = contacts
                .iter()
                .filter_map(|target| {
                    let cargo = target.cargo?;
                    let distance = point.distance(target.point);
                    if !target.flying
                        || !self.hostile(ship.owner, target.owner)
                        || distance > self.sensor_range(ship.owner, ship.role)
                        || self.room(home, cargo.resource) == 0
                    {
                        return None;
                    }
                    let meeting = target.intercept(point, profile.speed)?;
                    let trip_distance =
                        point.distance(meeting) + meeting.distance(location_point(self, home));
                    let fuel = (trip_distance * profile.fuel_rate).ceil() as u32 + 3;
                    let defenders = contacts
                        .iter()
                        .filter(|other| {
                            other.owner == target.owner
                                && other.armed
                                && other.flying
                                && other.point.distance(meeting) <= 2.0
                        })
                        .count();
                    let value = f64::from(cargo.quantity.min(12))
                        * f64::from(cargo.resource.base_price())
                        / 16.0;
                    let risk = defenders as f64
                        * if ship.owner == Faction::Pirates {
                            4.0
                        } else {
                            7.0
                        };
                    let score = value - trip_distance * 0.21 - risk - f64::from(ship.damage) * 0.08;
                    (score > 0.0).then_some((fuel <= available, score, target, fuel))
                })
                .max_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.total_cmp(&b.1)));
            let Some((_, score, target, fuel)) = target else {
                ship.status = "Ищет достижимый и выгодный рейс".into();
                return;
            };
            if fuel <= available {
                events.push(decision(
                    "raid_departed",
                    ship.owner.label(),
                    format!(
                        "{} выбрал {}. Оценка добычи с учётом расстояния, топлива и охраны {:.1}.",
                        ship.name, target.id, score
                    ),
                ));
            }
            (Duty::Raid(target.id.clone()), fuel, 100)
        } else {
            let route = contacts
                .iter()
                .filter(|target| {
                    target.owner == ship.owner && target.flying && target.cargo.is_some()
                })
                .filter_map(|target| target.lane.as_ref())
                .find(|lane| lane.as_str() != home);
            let anchor = route
                .cloned()
                .or_else(|| self.alert(ship.owner).then(|| crate::sim::BELT.into()));
            let Some(anchor) = anchor else {
                ship.status = "Ждёт грузовой трафик или сигнал угрозы".into();
                return;
            };
            let distance = point.distance(location_point(self, &anchor)) * 0.65;
            let fuel = (distance * 2.0 * profile.fuel_rate).ceil() as u32 + 5;
            (Duty::Patrol(anchor), fuel, 64)
        };
        if fuel > available {
            ship.status = "Ждёт топливо на вылет и возвращение".into();
            if self.room(&ship.location, Commodity::Fuel) > 0 && fuel <= ship.tank {
                let missing = fuel - available;
                self.fleet.request(
                    &ship.location,
                    Commodity::Fuel,
                    missing.min(self.room(&ship.location, Commodity::Fuel)),
                    35,
                );
            }
            return;
        }
        let refill = fuel.saturating_sub(ship.fuel);
        if refill > 0 {
            assert!(self.withdraw(&ship.location, Commodity::Fuel, refill));
            ship.fuel += refill;
        }
        ship.status = "Начинает вылет".into();
        ship.sortie = Some(Sortie {
            point,
            home: home.into(),
            duty,
            left,
            fuel_fraction: 0.0,
            prepaid_fuel: 0.0,
        });
    }

    fn exchange_fire(&mut self, contacts: &[Contact], events: &mut Vec<Event>) {
        let mut hits = BTreeMap::<String, u32>::new();
        let mut shooters = Vec::new();
        for attacker in contacts.iter().filter(|unit| unit.armed && unit.flying) {
            let ship = &self.fleet.ships[&attacker.id];
            if ship.weapon_wait != 0 || ship.sortie.is_none() {
                continue;
            }
            let profile = ship.role.loadout();
            let preferred = ship.sortie.as_ref().and_then(|flight| match &flight.duty {
                Duty::Raid(id) => Some(id),
                _ => None,
            });
            let target = contacts
                .iter()
                .filter(|target| {
                    target.flying
                        && self.hostile(ship.owner, target.owner)
                        && (target.armed || preferred == Some(&target.id))
                        && attacker.point.distance(target.point) <= profile.range
                })
                .min_by(|a, b| {
                    (!a.armed).cmp(&(!b.armed)).then_with(|| {
                        attacker
                            .point
                            .distance(a.point)
                            .total_cmp(&attacker.point.distance(b.point))
                    })
                });
            if let Some(target) = target {
                let intel = self.security.intel.entry(target.owner).or_default();
                intel.attacks_suffered += 1;
                intel.last_threat = Some(self.seconds);
                *hits.entry(target.id.clone()).or_default() += profile.damage;
                shooters.push((attacker.id.clone(), profile.cooldown));
                events.push(decision(
                    "combat_hit",
                    ship.owner.label(),
                    format!(
                        "{} → {}. Урон {}.",
                        ship.name, self.fleet.ships[&target.id].name, profile.damage
                    ),
                ));
            }
        }
        for (id, delay) in shooters {
            self.fleet.ships.get_mut(&id).unwrap().weapon_wait = delay;
        }
        for (id, damage) in hits {
            let ship = self.fleet.ships.get_mut(&id).unwrap();
            ship.damage = ship.damage.saturating_add(damage);
            if ship.damage < ship.role.loadout().hull {
                continue;
            }
            let ship = self.fleet.ships.remove(&id).unwrap();
            let intel = self.security.intel.entry(ship.owner).or_default();
            intel.casualties += 1;
            if ship.owner == Faction::Pirates && ship.role == ShipRole::Raider {
                self.conflict.intercepted_raids += 1;
            }
            let lost = ship
                .task
                .as_ref()
                .filter(|task| task.loaded)
                .map_or(0, |task| task.quantity)
                + ship.spoils.map_or(0, |cargo| cargo.quantity);
            events.push(decision(
                "ship_destroyed",
                ship.owner.label(),
                format!(
                    "{} уничтожен. Потеряно {lost} ед. груза. Недопоставка остаётся открытой.",
                    ship.name
                ),
            ));
        }
    }

    fn capture_cargo(&mut self, contacts: &[Contact], events: &mut Vec<Event>) {
        let raiders: Vec<_> = self
            .fleet
            .ships
            .iter()
            .filter_map(|(id, ship)| {
                let flight = ship.sortie.as_ref()?;
                let Duty::Raid(target) = &flight.duty else {
                    return None;
                };
                Some((id.clone(), target.clone(), flight.point, ship.owner))
            })
            .collect();
        for (raider, target, point, owner) in raiders {
            let Some(contact) = contacts
                .iter()
                .find(|unit| unit.id == target && unit.flying)
            else {
                continue;
            };
            if point.distance(contact.point) > BOARDING_RANGE
                || !self.hostile(owner, contact.owner)
                || contacts.iter().any(|guard| {
                    guard.owner == contact.owner
                        && guard.armed
                        && guard.flying
                        && self.fleet.ships.contains_key(&guard.id)
                        && guard.point.distance(point) <= 0.9
                })
            {
                continue;
            }
            let Some(cargo) = contact.cargo else { continue };
            let room = self.room(owner.home(), cargo.resource);
            let Some(task) = self
                .fleet
                .ships
                .get_mut(&target)
                .and_then(|ship| ship.task.as_mut())
                .filter(|task| task.loaded)
            else {
                continue;
            };
            let quantity = task.quantity.min(12).min(room);
            if quantity == 0 {
                continue;
            }
            task.quantity -= quantity;
            let ship = self.fleet.ships.get_mut(&raider).unwrap();
            ship.spoils = Some(Spoils {
                resource: cargo.resource,
                quantity,
            });
            ship.sortie.as_mut().unwrap().duty = Duty::Return;
            self.security.intel.entry(owner).or_default().loot_taken += quantity;
            let defender = self.security.intel.entry(contact.owner).or_default();
            defender.loot_lost += quantity;
            defender.last_threat = Some(self.seconds);
            if cargo.resource == Commodity::Ore && contact.owner == Faction::Genesis {
                self.conflict.lost_ore += quantity;
            }
            events.push(decision(
                "raid_stolen",
                owner.label(),
                format!(
                    "{} захватил {quantity} ед. {} с {}.",
                    ship.name,
                    cargo.resource.as_str(),
                    target
                ),
            ));
        }
    }

    pub(crate) fn migrate_security(&mut self) {
        if self.security.initialized {
            return;
        }
        self.security.initialized = true;
        self.import_pirate_stock();
        let war = &self.conflict;
        if war.lost_ore > 0 {
            self.security.intel.insert(
                Faction::Genesis,
                Intel {
                    loot_lost: war.lost_ore,
                    last_threat: Some(self.seconds),
                    ..Intel::default()
                },
            );
        }
        let seed_guard = war.patrol == Patrol::Ready;
        let seed_raider = war.base_progress >= 40.0 && !war.raider_destroyed;
        let raid_from = location_point(self, PIRATE_BASE);
        let raid_to = location_point(self, war.raid_source.as_deref().unwrap_or(crate::sim::BELT));
        let raid_progress = if war.raider_return > 0.0 {
            war.retreat_from * (1.0 - war.raider_return / war.return_duration())
        } else {
            war.raid_elapsed / war.approach_duration()
        }
        .clamp(0.0, 1.0);
        let patrol_progress = war.patrol_progress().clamp(0.0, 1.0);
        let guard_from = location_point(self, EARTH);
        let guard_to = location_point(self, crate::sim::BELT);
        for (owner, role, spawn, generation, fuel, damage, progress, from, to) in [
            (
                Faction::Pirates,
                ShipRole::Raider,
                seed_raider,
                war.raider_generation,
                war.raider_fuel,
                war.raider_damage,
                raid_progress,
                raid_from,
                raid_to,
            ),
            (
                Faction::Genesis,
                ShipRole::Patrol,
                seed_guard,
                war.patrol_generation,
                war.patrol_fuel,
                war.patrol_damage,
                patrol_progress,
                guard_from,
                guard_to,
            ),
        ] {
            if !spawn {
                continue;
            }
            let mut ship = Ship::new(role.label(), owner.home(), fuel, owner, role);
            ship.damage = damage.min(role.loadout().hull - 1);
            if owner == Faction::Pirates && war.raider_cargo > 0 {
                ship.spoils = Some(Spoils {
                    resource: Commodity::Ore,
                    quantity: war.raider_cargo,
                });
            }
            if progress > 0.0 {
                let point = Point {
                    x: from.x + (to.x - from.x) * progress,
                    y: from.y + (to.y - from.y) * progress,
                };
                let duty = if owner == Faction::Pirates && war.raider_return == 0.0 {
                    war.raid_target
                        .clone()
                        .map(Duty::Raid)
                        .unwrap_or(Duty::Return)
                } else {
                    Duty::Return
                };
                let prepaid_distance = if matches!(duty, Duty::Raid(_)) {
                    point.distance(to) + to.distance(from)
                } else {
                    point.distance(from)
                };
                ship.sortie = Some(Sortie {
                    point,
                    home: owner.home().into(),
                    duty,
                    left: 80,
                    fuel_fraction: 0.0,
                    prepaid_fuel: prepaid_distance * role.loadout().fuel_rate + 2.0,
                });
            }
            self.fleet.ships.insert(
                format!(
                    "{}-{}",
                    if owner == Faction::Pirates {
                        "raider"
                    } else {
                        "patrol"
                    },
                    generation + 1
                ),
                ship,
            );
        }
        if war.raider_destroyed {
            self.security
                .intel
                .entry(Faction::Pirates)
                .or_default()
                .casualties = 1;
            if war.rebuild_elapsed > 0.0 {
                self.security.legacy_orders.push(LegacyHull {
                    role: ShipRole::Raider,
                    owner: Faction::Pirates,
                    id: format!("raider-{}", war.raider_generation + 2),
                    fuel: 2,
                    remaining: ((16.0 - war.rebuild_elapsed).max(STEP) / STEP).ceil() as u32,
                });
            }
        }
        if matches!(
            war.patrol,
            Patrol::Delivering | Patrol::Building | Patrol::Rebuilding
        ) {
            let duration = match war.patrol {
                Patrol::Delivering => 12.0,
                Patrol::Building => 8.0,
                _ => 16.0,
            };
            self.security.legacy_orders.push(LegacyHull {
                role: ShipRole::Patrol,
                owner: Faction::Genesis,
                id: format!(
                    "patrol-{}",
                    war.patrol_generation + 1 + u32::from(war.patrol == Patrol::Rebuilding)
                ),
                fuel: 4,
                remaining: ((duration - war.patrol_elapsed).max(STEP) / STEP).ceil() as u32,
            });
        }
    }
}
