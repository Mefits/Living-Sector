use crate::builds::Faction;
use crate::security::{Sortie, Spoils};
use crate::sim::{Event, Sim};
use serde::{Deserialize, Serialize};
pub use sim_core::economy::commodities::Commodity;
use std::collections::BTreeMap;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Fleet {
    #[serde(default)]
    pub initialized: bool,
    pub ships: BTreeMap<String, Ship>,
    pub orders: BTreeMap<String, Order>,
    pub next_order: u64,
}

impl Default for Fleet {
    fn default() -> Self {
        Self {
            initialized: false,
            ships: BTreeMap::new(),
            orders: BTreeMap::new(),
            next_order: 1,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Ship {
    #[serde(default)]
    pub owner: Faction,
    #[serde(default)]
    pub damage: u32,
    #[serde(default)]
    pub weapon_wait: u32,
    #[serde(default)]
    pub duty_wait: u32,
    #[serde(default)]
    pub sortie: Option<Sortie>,
    #[serde(default)]
    pub spoils: Option<Spoils>,
    #[serde(default)]
    pub role: ShipRole,
    pub name: String,
    pub location: String,
    pub fuel: u32,
    pub tank: u32,
    pub capacity: u32,
    pub task: Option<Assignment>,
    pub leg: Option<Leg>,
    pub status: String,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ShipRole {
    #[default]
    Freighter,
    Constructor,
    Patrol,
    Raider,
}

impl ShipRole {
    pub fn is_combat(self) -> bool {
        matches!(self, Self::Patrol | Self::Raider)
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Freighter => "Грузовой",
            Self::Constructor => "Строитель",
            Self::Patrol => "Патруль",
            Self::Raider => "Рейдер",
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Leg {
    pub destination: String,
    pub duration: u32,
    pub elapsed: u32,
}

impl Leg {
    pub fn progress(&self) -> f64 {
        sim_core::world::travel::transit_progress(
            u64::from(self.elapsed),
            0,
            u64::from(self.duration),
        ) as f64
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Order {
    pub destination: String,
    pub resource: Commodity,
    pub remaining: u32,
    pub priority: u32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Assignment {
    pub order: String,
    pub source: String,
    pub quantity: u32,
    pub loaded: bool,
    pub handling: u32,
}

impl Ship {
    pub fn freighter(name: impl Into<String>, location: &str, fuel: u32) -> Self {
        Self::new(name, location, fuel, Faction::Genesis, ShipRole::Freighter)
    }

    pub fn new(
        name: impl Into<String>,
        location: &str,
        fuel: u32,
        owner: Faction,
        role: ShipRole,
    ) -> Self {
        Self {
            owner,
            damage: 0,
            weapon_wait: 0,
            duty_wait: 0,
            sortie: None,
            spoils: None,
            role,
            name: name.into(),
            location: location.into(),
            fuel,
            tank: if role.is_combat() { 36 } else { 100 },
            capacity: match role {
                ShipRole::Freighter => 50,
                ShipRole::Constructor => 40,
                ShipRole::Patrol => 0,
                ShipRole::Raider => 12,
            },
            task: None,
            leg: None,
            status: "Ждёт задание".into(),
        }
    }
}

impl Fleet {
    pub fn request(
        &mut self,
        destination: &str,
        resource: Commodity,
        amount: u32,
        priority: u32,
    ) -> String {
        if let Some((id, order)) = self
            .orders
            .iter_mut()
            .find(|(_, order)| order.resource == resource && order.destination == destination)
        {
            order.priority = priority;
            return id.clone();
        }
        let id = self.next_order.to_string();
        self.next_order += 1;
        self.orders.insert(
            id.clone(),
            Order {
                destination: destination.into(),
                resource,
                remaining: amount,
                priority,
            },
        );
        id
    }

    pub fn incoming(&self, destination: &str, resource: Commodity) -> u32 {
        self.ships
            .values()
            .filter_map(|ship| ship.task.as_ref())
            .filter(|task| {
                self.orders.get(&task.order).is_some_and(|order| {
                    order.destination == destination && order.resource == resource
                })
            })
            .map(|task| task.quantity)
            .sum()
    }

    pub fn reserved(&self, source: &str, resource: Commodity) -> u32 {
        self.ships
            .values()
            .filter_map(|ship| ship.task.as_ref())
            .filter(|task| {
                !task.loaded
                    && task.source == source
                    && self
                        .orders
                        .get(&task.order)
                        .is_some_and(|order| order.resource == resource)
            })
            .map(|task| task.quantity)
            .sum()
    }

    pub fn valid(&self) -> bool {
        self.orders
            .keys()
            .all(|id| id.parse::<u64>().is_ok_and(|id| id < self.next_order))
            && self.ships.values().all(|ship| {
                ship.fuel <= ship.tank
                    && ship.damage < ship.role.loadout().hull
                    && ship.spoils.is_none_or(|spoils| {
                        spoils.quantity > 0 && spoils.quantity <= ship.capacity
                    })
                    && ship.sortie.as_ref().is_none_or(|flight| {
                        ship.role.is_combat()
                            && ship.leg.is_none()
                            && ship.task.is_none()
                            && flight.point.x.is_finite()
                            && flight.point.y.is_finite()
                            && (0.0..1.0).contains(&flight.fuel_fraction)
                            && flight.prepaid_fuel.is_finite()
                            && flight.prepaid_fuel >= 0.0
                    })
                    && ship
                        .leg
                        .as_ref()
                        .is_none_or(|leg| leg.duration > 0 && leg.elapsed < leg.duration)
                    && ship.task.as_ref().is_none_or(|task| {
                        task.quantity <= ship.capacity && self.orders.contains_key(&task.order)
                    })
            })
    }

    pub fn advance(&mut self, sim: &mut Sim, events: &mut Vec<Event>) {
        // One deterministic commit sequence. Reservation, pickup and delivery all see prior changes.
        let ids: Vec<_> = self.ships.keys().cloned().collect();
        for id in ids {
            if sim.builds.builder_job(&id).is_some() || sim.legacy_builder_busy(&id) {
                continue;
            }
            let mut ship = self.ships.remove(&id).expect("known ship");
            self.advance_ship(sim, events, &mut ship);
            self.ships.insert(id, ship);
        }
        self.orders.retain(|_, order| order.remaining > 0);
    }

    fn advance_ship(&mut self, sim: &mut Sim, events: &mut Vec<Event>, ship: &mut Ship) {
        if let Some(leg) = &mut ship.leg {
            leg.elapsed += 1;
            if leg.elapsed == leg.duration {
                ship.location = std::mem::take(&mut leg.destination);
                ship.leg = None;
            }
            return;
        }
        if ship.role.is_combat() {
            return;
        }
        if ship.task.is_none() {
            self.assign(sim, ship);
        }
        let Some(mut task) = ship.task.take() else {
            return;
        };
        let order = self.orders[&task.order].clone();
        let destination = if task.loaded {
            &order.destination
        } else {
            &task.source
        };
        if &ship.location != destination {
            let fuel = sim.travel(&ship.location, destination).1;
            if ship.fuel < fuel {
                let refill = fuel - ship.fuel;
                let cargo_reserve = if !task.loaded
                    && order.resource == Commodity::Fuel
                    && ship.location == task.source
                {
                    task.quantity
                } else {
                    0
                };
                let available = sim.refuel_supply(&ship.location).saturating_sub(
                    self.reserved(&ship.location, Commodity::Fuel)
                        .saturating_add(cargo_reserve),
                );
                if refill <= available
                    && fuel <= ship.tank
                    && sim.withdraw(&ship.location, Commodity::Fuel, refill)
                {
                    ship.fuel += refill;
                }
            }
            if ship.fuel < fuel {
                // Empty assignments can release stock; loaded cargo stays on the ship.
                if task.loaded {
                    ship.task = Some(task);
                }
                ship.status = "Ждёт топливо".into();
                return;
            }
            self.depart(sim, ship, destination);
            ship.task = Some(task);
            return;
        }
        task.handling += 1;
        if task.handling < 12 {
            ship.status = if task.loaded {
                "Разгрузка"
            } else {
                "Погрузка"
            }
            .into();
            ship.task = Some(task);
            return;
        }
        task.handling = 0;
        if !task.loaded {
            if sim.freight_supply(&task.source, order.resource) >= task.quantity
                && sim.withdraw(&task.source, order.resource, task.quantity)
            {
                task.loaded = true;
                events.push(sim.freight_event(
                    "loaded",
                    order.resource,
                    &task.source,
                    task.quantity,
                    &ship.name,
                ));
                ship.task = Some(task);
            } else {
                ship.status = "Товар больше недоступен".into();
            }
        } else {
            let quantity = task
                .quantity
                .min(sim.room(&order.destination, order.resource));
            sim.deposit_cargo(&order.destination, order.resource, quantity);
            self.orders.get_mut(&task.order).unwrap().remaining =
                order.remaining.saturating_sub(quantity);
            task.quantity -= quantity;
            if quantity > 0 {
                events.push(sim.freight_event(
                    "unloaded",
                    order.resource,
                    &order.destination,
                    quantity,
                    &ship.name,
                ));
            }
            if task.quantity > 0 {
                ship.status = "Ждёт место на складе".into();
                ship.task = Some(task);
            } else {
                ship.status = "Ждёт задание".into();
            }
        }
    }

    fn assign(&mut self, sim: &mut Sim, ship: &mut Ship) {
        let mut best = None;
        for (id, order) in &self.orders {
            if ship.role == ShipRole::Constructor
                && order.priority < 35
                && self.ships.values().any(|candidate| {
                    candidate.owner == ship.owner && candidate.role == ShipRole::Freighter
                })
            {
                continue;
            }
            if sim.location_owner(&order.destination) != ship.owner {
                continue;
            }
            let demand = order
                .remaining
                .saturating_sub(self.incoming(&order.destination, order.resource));
            if demand == 0 {
                continue;
            }
            for source in sim.locations() {
                if source == order.destination
                    || sim.location_owner(source) != ship.owner
                    || !sim.available_location(source)
                {
                    continue;
                }
                let available = sim
                    .freight_supply(source, order.resource)
                    .saturating_sub(self.reserved(source, order.resource));
                let cost =
                    sim.travel(&ship.location, source).1 + sim.travel(source, &order.destination).1;
                let local_fuel = sim
                    .refuel_supply(&ship.location)
                    .saturating_sub(self.reserved(&ship.location, Commodity::Fuel));
                let refill = cost.saturating_sub(ship.fuel);
                let quantity = ship
                    .capacity
                    .min(demand)
                    .min(sim.room(&order.destination, order.resource))
                    .min(available.saturating_sub(
                        if source == ship.location && order.resource == Commodity::Fuel {
                            refill
                        } else {
                            0
                        },
                    ));
                let lot = ship
                    .capacity
                    .min(demand)
                    .min(sim.room(&order.destination, order.resource))
                    .min(crate::sim::SHIPMENT);
                let extractable = sim.extractable(source, order.resource);
                let waiting_for_batch = extractable > 0
                    && quantity < lot
                    && quantity.saturating_add(extractable) >= lot
                    && quantity.saturating_add(sim.room(source, order.resource)) >= lot;
                if quantity == 0 || waiting_for_batch || cost > ship.tank || refill > local_fuel {
                    continue;
                }
                let score = (order.priority, std::cmp::Reverse(cost), quantity);
                if best
                    .as_ref()
                    .is_none_or(|(previous, _, _, _)| score > *previous)
                {
                    best = Some((score, id.clone(), source.to_string(), refill));
                }
            }
        }
        if let Some(((_, _, quantity), id, source, refill)) = best {
            if refill > 0 {
                assert!(sim.withdraw(&ship.location, Commodity::Fuel, refill));
                ship.fuel += refill;
            }
            ship.task = Some(Assignment {
                order: id,
                source: source.into(),
                quantity,
                loaded: false,
                handling: 0,
            });
        } else {
            ship.status = "Ждёт доступное задание, маршрут или топливо".into();
        }
    }

    fn depart(&self, sim: &Sim, ship: &mut Ship, destination: &str) {
        let (duration, cost) = sim.travel(&ship.location, destination);
        ship.fuel -= cost;
        ship.leg = Some(Leg {
            destination: destination.into(),
            duration,
            elapsed: 0,
        });
        ship.status = "В пути".into();
    }
}
