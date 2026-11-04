use crate::builds::{Faction, SiteJob};
use crate::conflict::PIRATE_BASE;
use crate::freight::{Commodity, Order, Ship, ShipRole};
use crate::industry::{Deposit, Operation, Plant};
use crate::planning::{Choice, Kind, Site};
use crate::sim::{Event, Sim, decision_at};
use std::collections::BTreeSet;

impl Sim {
    pub(crate) fn home_port(&self, owner: Faction) -> &str {
        self.governance
            .economies
            .get(&owner)
            .map_or(owner.legacy_home(), |policy| &policy.home)
    }

    pub(crate) fn economic_owners(&self) -> impl Iterator<Item = Faction> + use<> {
        self.warehouses
            .values()
            .map(|warehouse| warehouse.owner)
            .filter(|&owner| {
                self.warehouses
                    .get(self.home_port(owner))
                    .is_some_and(|port| port.owner == owner)
            })
            .collect::<BTreeSet<_>>()
            .into_iter()
    }

    pub(crate) fn economic_policy(&self, owner: Faction) -> (u32, u32, Option<ShipRole>) {
        if let Some(policy) = self.governance.economies.get(&owner) {
            return (policy.fuel_reserve, policy.fuel_target, policy.military);
        }
        match owner {
            Faction::Genesis => {
                let reserve = self.governance.leader.reserve();
                (reserve, reserve + 24, Some(ShipRole::Patrol))
            }
            Faction::Pirates => (2, 18, Some(ShipRole::Raider)),
            Faction::Independent(_) => (0, 0, None),
        }
    }

    pub(crate) fn seed_starting_industry(&mut self) {
        for (id, resource, quantity) in [
            ("jupiter-vein", Commodity::Ore, 280),
            ("jupiter-gas", Commodity::Gas, 900),
        ] {
            self.industry.deposits.insert(
                id.into(),
                Deposit {
                    resource,
                    initial: quantity,
                    remaining: quantity,
                },
            );
        }
        let owner = Faction::Pirates;
        let choice = Choice {
            kind: Kind::Mine,
            site: Site::Jupiter,
        };
        self.builds.projects.insert(
            "jupiter-mining".into(),
            SiteJob {
                owner,
                choice,
                done: true,
                journey: None,
                legacy: false,
                supply_port: None,
            },
        );
        self.activate_structure("jupiter-mining", owner, choice, false);
        let base = self.warehouses.get_mut(PIRATE_BASE).expect("starting base");
        for (resource, capacity) in [
            (Commodity::Ore, 60),
            (Commodity::Metals, 80),
            (Commodity::Gas, 60),
            (Commodity::Fuel, 100),
        ] {
            base.limits.insert(resource, capacity);
        }
        self.industry.plants.insert(
            "jupiter-smelter".into(),
            Plant::process(PIRATE_BASE, 20, "smelt_metals"),
        );
        self.industry.plants.insert(
            "jupiter-refinery".into(),
            Plant::process(PIRATE_BASE, 16, "crack_fuel"),
        );
        let mut collector = Plant::extract(PIRATE_BASE, 16, 12);
        collector.operation = Operation::Extract {
            deposit: "jupiter-gas".into(),
            amount: 12,
        };
        self.industry
            .plants
            .insert("jupiter-collector".into(), collector);
        // The transport and its initial tank are part of the expedition manifest.
        self.fleet.ships.insert(
            "jupiter-freighter".into(),
            Ship::new(
                "Транспорт Юпитера",
                PIRATE_BASE,
                16,
                owner,
                ShipRole::Freighter,
            ),
        );
    }

    pub(crate) fn plan_fuel(&mut self) {
        for owner in self
            .economic_owners()
            .filter(|&owner| self.faction_ready(owner))
            .collect::<Vec<_>>()
        {
            let port = self.home_port(owner).to_owned();
            let (_, target, _) = self.economic_policy(owner);
            let needed = target
                .saturating_sub(self.stock(&port, Commodity::Fuel))
                .min(self.room(&port, Commodity::Fuel));
            if needed > 0 {
                self.fleet.request(&port, Commodity::Fuel, needed, 20);
            }
        }
    }

    pub(crate) fn plan_storage(&mut self) {
        let mut orders = Vec::new();
        for plant in self.industry.plants.values() {
            let Some(recipe) = plant.recipe() else {
                continue;
            };
            let origin = &plant.location;
            for &(resource, batch) in recipe.outputs {
                if self.room(origin, resource) >= batch {
                    continue;
                }
                let keep = if resource == Commodity::Metals {
                    32
                } else {
                    batch
                };
                let surplus = self
                    .production_supply(origin, resource)
                    .saturating_sub(keep);
                let owner = self.location_owner(origin);
                let destination = self.builds.projects.iter().find_map(|(id, job)| {
                    (id != origin
                        && job.owner == owner
                        && job.done
                        && job.choice.kind == Kind::Warehouse
                        && self.room(id, resource) >= batch)
                        .then_some(id)
                });
                if let Some(id) = destination {
                    let quantity = surplus.min(self.room(id, resource)).min(40);
                    if quantity >= batch {
                        orders.push((id.clone(), resource, quantity));
                    }
                }
            }
        }
        for (id, resource, quantity) in orders {
            self.fleet.request(&id, resource, quantity, 8);
        }
    }

    fn installed_sources<'a>(
        &'a self,
        owner: Faction,
        resource: Commodity,
    ) -> impl Iterator<Item = &'a Plant> + 'a {
        self.industry.plants.values().filter(move |plant| {
            self.location_owner(&plant.location) == owner
                && match &plant.operation {
                    Operation::Extract { deposit, .. } => {
                        self.industry.deposits[deposit].resource == resource
                    }
                    Operation::Process { .. } => plant.recipe().is_some_and(|recipe| {
                        recipe.outputs.iter().any(|&(output, _)| output == resource)
                    }),
                }
        })
    }

    pub(crate) fn has_producer(&self, owner: Faction, resource: Commodity) -> bool {
        self.installed_sources(owner, resource)
            .any(|plant| match &plant.operation {
                Operation::Extract { deposit, .. } => {
                    self.deposit_remaining(deposit) > 0 || plant.batch.is_some()
                }
                Operation::Process { .. } => true,
            })
    }

    pub(crate) fn construction_budget(&self, port: &str, resource: Commodity) -> u32 {
        let local = self.production_supply(port, resource);
        let owner = self.location_owner(port);
        let room = self.room(port, resource);
        let stock = self
            .locations()
            .filter(|&source| source != port && self.location_owner(source) == owner)
            .map(|source| {
                self.freight_supply(source, resource)
                    .saturating_sub(self.fleet.reserved(source, resource))
            })
            .fold(0u32, u32::saturating_add);
        let accessible = if self.has_producer(owner, resource) {
            room
        } else {
            stock.min(room)
        };
        local.saturating_add(accessible)
    }

    pub(crate) fn order_status(&self, order: &Order) -> String {
        let destination = &order.destination;
        let resource = order.resource;
        if self.fleet.incoming(destination, resource) >= order.remaining {
            return "Назначено к доставке".into();
        }
        if self.room(destination, resource) == 0 {
            return "Нет места у получателя".into();
        }
        let owner = self.location_owner(destination);
        let sources: Vec<_> = self
            .locations()
            .filter(|&source| {
                source != destination
                    && self.location_owner(source) == owner
                    && self.freight_supply(source, resource) > self.fleet.reserved(source, resource)
            })
            .collect();
        if !sources.is_empty() {
            let eligible = self
                .fleet
                .ships
                .iter()
                .filter(|(id, ship)| {
                    ship.owner == owner
                        && !ship.role.is_combat()
                        && ship.capacity > 0
                        && (ship.role == ShipRole::Freighter
                            || order.priority >= 35
                            || !self.fleet.ships.values().any(|other| {
                                other.owner == owner && other.role == ShipRole::Freighter
                            }))
                        && self.builds.builder_job(id).is_none()
                        && !self.legacy_builder_busy(id)
                })
                .collect::<Vec<_>>();
            if eligible.is_empty() {
                return "Нет доступного перевозчика".into();
            }
            if eligible
                .iter()
                .all(|(_, ship)| ship.task.is_some() || ship.leg.is_some())
            {
                return "Перевозчики заняты".into();
            }
            let reachable = eligible.iter().any(|(_, ship)| {
                sources.iter().any(|&source| {
                    let cost = self
                        .travel(&ship.location, source)
                        .1
                        .saturating_add(self.travel(source, destination).1);
                    cost <= ship.tank
                        && cost
                            <= ship.fuel.saturating_add(
                                self.refuel_supply(&ship.location).saturating_sub(
                                    self.fleet.reserved(&ship.location, Commodity::Fuel),
                                ),
                            )
                })
            });
            return if reachable {
                "Ждёт назначения рейса"
            } else {
                "Не хватает топлива на доступный маршрут"
            }
            .into();
        }
        if let Some(plant) = self.installed_sources(owner, resource)
            .find(|plant| plant.batch.is_some() || !matches!(&plant.operation, Operation::Extract { deposit, .. } if self.deposit_remaining(deposit) == 0))
        {
            return format!("Источник {} · {}", plant.location, plant.status(self));
        }
        if self.installed_sources(owner, resource).next().is_some() {
            "Доступные залежи исчерпаны".into()
        } else {
            "Нет доступного источника у фракции".into()
        }
    }

    pub(crate) fn port_blockers(&self, owner: Faction) -> Vec<String> {
        self.fleet
            .orders
            .values()
            .filter(|order| self.location_owner(&order.destination) == owner)
            .map(|order| {
                format!(
                    "{} · {} × {} · {}",
                    order.destination,
                    order.resource.as_str(),
                    order.remaining,
                    self.order_status(order)
                )
            })
            .collect()
    }

    pub(crate) fn record_priority(
        &self,
        owner: Faction,
        priority: &str,
        blockers: &[String],
    ) -> Event {
        let home = self.home_port(owner);
        let reason = if blockers.is_empty() {
            priority.to_owned()
        } else {
            format!("{priority}. {}", blockers.join(" | "))
        };
        decision_at("faction_priority", owner, home, reason)
    }
}
