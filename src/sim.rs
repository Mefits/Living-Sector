use crate::conflict::{
    Conflict, PATROL_DURATION, PATROL_METAL, PATROL_SEED_FUEL, PIRATE_BASE, PIRATE_SEED_METAL,
    Patrol,
};
use crate::construction::{
    COMMISSION_FUEL, Construction, MARS_ORE, MARS_SITE, MarsProject, Project, SHIP_METAL,
    YARD_METAL,
};
use crate::governance::Governance;
use crate::freight::Freighter;
use crate::planning::{self, Kind, Program, Site as BuildSite};
use serde::{Deserialize, Serialize};

pub const SHIPMENT: u32 = 50;
pub const TANK: u32 = 100;
pub const BELT: &str = "belt-outpost";
pub const EARTH: &str = "earth-station";
pub const SHIP: &str = "Грузовой-001";
const FLIGHT_FUEL: u32 = 8;
const FUEL_SHIPMENT: u32 = 24;
const MINE_INTERVAL: f64 = 2.0;
const BELT_CAPACITY: u32 = 100;
const SMELT_INTERVAL: f64 = 5.0;
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

impl Phase {
    pub fn duration(self) -> f64 {
        match self {
            Self::Loading | Self::Unloading => 3.0,
            Self::Outbound | Self::Returning | Self::Relocating => 16.0,
            Self::Waiting | Self::NoFuelAtBelt | Self::NoFuelAtEarth => f64::INFINITY,
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Sim {
    pub phase: Phase,
    pub elapsed: f64,
    pub seconds: f64,
    pub tick: u64,
    pub belt_ore: u32,
    pub station_ore: u32,
    pub cargo: u32,
    #[serde(default)]
    pub fuel_cargo: u32,
    #[serde(default)]
    fuel_order: bool,
    pub fuel: u32,
    pub belt_fuel: u32,
    pub station_fuel: u32,
    #[serde(default)]
    pub metal: u32,
    #[serde(default)]
    mining_elapsed: f64,
    #[serde(default)]
    smelting_elapsed: f64,
    #[serde(default)]
    pending: f64,
    #[serde(default)]
    pub governance: Governance,
    #[serde(default)]
    pub construction: Construction,
    #[serde(default)]
    pub second_freighter: Option<Freighter>,
    #[serde(default = "seed_ore")]
    pub deposit: u32,
    #[serde(default)]
    pub conflict: Conflict,
    #[serde(default)]
    pub mars_route: bool,
    #[serde(default)]
    pub genesis_program: Program,
    #[serde(default)]
    pub pirate_program: Program,
    #[serde(default)]
    pub outpost_site: Option<BuildSite>,
    #[serde(default)]
    route_duration: f64,
    #[serde(default)]
    return_duration: f64,
    #[serde(default)]
    return_fuel: u32,
    #[serde(default)]
    outbound_plan: (f64, u32),
}

#[derive(Clone, Serialize)]
pub struct Event {
    kind: &'static str,
    commodity: &'static str,
    location: &'static str,
    quantity: u32,
    stock: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    ship_name: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub actor: Option<&'static str>,
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
            return_fuel: 0,
            outbound_plan: (0.0, 0),
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
        let has_cargo = matches!(self.phase, Phase::Outbound | Phase::Unloading);
        self.seconds.is_finite()
            && self.seconds >= 0.0
            && (0.0..self.freight_duration()).contains(&self.elapsed)
            && (if has_cargo {
                (self.fuel_cargo == FUEL_SHIPMENT && self.cargo == 0 && self.fuel_order)
                    || (self.fuel_cargo == 0 && (SHIPMENT - 10..=SHIPMENT).contains(&self.cargo))
            } else {
                self.cargo == 0 && self.fuel_cargo == 0
            })
            && self.belt_ore <= BELT_CAPACITY
            && (self.phase != Phase::Loading
                || self.fuel_order
                || self.mars_route
                || self.belt_ore >= SHIPMENT)
            && self.fuel <= TANK
            && self.station_fuel <= 200
            && self.belt_fuel <= 200
            && self.station_ore <= 5_000
            && self.metal <= self.metal_capacity()
            && (0.0..MINE_INTERVAL).contains(&self.mining_elapsed)
            && (0.0..SMELT_INTERVAL).contains(&self.smelting_elapsed)
            && (!self.batch_active()
                || (self.station_ore >= 10
                    && self.station_fuel > 0
                    && self.metal + 8 <= self.metal_capacity()))
            && (0.0..QUANTUM).contains(&self.pending)
            && self.conflict.raider_cargo <= 10
            && self.conflict.patrol_fuel <= PATROL_SEED_FUEL
            && (0.0..self.conflict.approach_duration()).contains(&self.conflict.raid_elapsed)
            && (0.0..self.conflict.return_duration()).contains(&self.conflict.raider_return)
            && (0.0..PATROL_DURATION).contains(&self.conflict.patrol_cycle)
            && (0.0..=1.0).contains(&self.conflict.retreat_from)
            && self.outbound_plan.1 <= TANK
            && self.return_fuel <= TANK
            && self.route_duration >= 0.0
            && self.route_duration.is_finite()
            && self.return_duration >= 0.0
            && self.return_duration.is_finite()
            && self.outbound_plan.0 >= 0.0
            && self.outbound_plan.0.is_finite()
            && (!self.mars_route
                || self.phase != Phase::Loading
                || self.construction.mars_ore >= SHIPMENT)
            && (self.phase != Phase::Loading || self.fuel >= self.outbound_plan.1)
            && (!self.fuel_order || self.phase != Phase::Loading || self.belt_fuel >= FUEL_SHIPMENT)
            && self.construction.mars_ore <= SHIPMENT
            && self.construction.mars_extracted <= MARS_ORE
            && self.deposit <= SEED_ORE
            && self.construction.parked_fuel <= TANK
            && (0.0..self.construction.duration()).contains(&self.construction.elapsed)
            && (!self.construction.active_second || self.construction.phase == Project::Complete)
            && self.second_freighter.as_ref().is_none_or(Freighter::valid)
            && self.tick < u64::MAX
    }

    pub fn delivery_active(&self) -> bool {
        matches!(
            self.phase,
            Phase::Relocating | Phase::Loading | Phase::Outbound | Phase::Unloading
        )
    }

    pub fn delivery_status(&self) -> &'static str {
        if self.delivery_active() {
            "Выполняется"
        } else if self.governance.ore_requested {
            if matches!(self.phase, Phase::NoFuelAtBelt | Phase::NoFuelAtEarth) {
                "Ждёт топливо для рейса"
            } else {
                "Ожидает грузовик"
            }
        } else if !self.has_ore_use() {
            "Плавка ограничена"
        } else {
            "Запас достаточный"
        }
    }

    fn has_ore_use(&self) -> bool {
        self.metal + 8 <= self.metal_capacity()
            && self.station_fuel > self.governance.leader.reserve()
    }

    pub fn smelting_cycle(&self) -> (f64, f64) {
        let duration = if self.genesis_program.has(Kind::Smelter) {
            3.5
        } else {
            SMELT_INTERVAL
        };
        (self.smelting_elapsed, duration)
    }

    pub fn mining_cycle(&self, source: &str) -> (f64, &'static str) {
        let mars = source == MARS_SITE;
        let (stock, deposit) = if mars {
            (
                self.construction.mars_ore,
                MARS_ORE - self.construction.mars_extracted,
            )
        } else {
            (self.belt_ore, self.deposit)
        };
        if stock >= SHIPMENT {
            (0.0, "Партия готова к погрузке")
        } else if deposit == 0 {
            (0.0, "Залежь исчерпана")
        } else if self.governance.ore_requested
            && !self.delivery_active()
            && self.prefer_mars() == mars
        {
            (self.mining_elapsed / MINE_INTERVAL, "Добывает руду")
        } else {
            (0.0, "Ждёт заявку снабженца")
        }
    }

    pub fn batch_active(&self) -> bool {
        self.smelting_elapsed > 0.0
    }

    pub fn smelting_status(&self) -> &'static str {
        if self.batch_active() {
            "Плавит руду"
        } else if self.metal + 8 > self.metal_capacity() {
            "Склад металла заполнен"
        } else if self.station_fuel == 0 {
            "Ждёт топливо"
        } else if self.station_fuel <= self.governance.fuel_floor() {
            "Топливо зарезервировано политикой"
        } else if self.station_fuel <= self.governance.leader.reserve() {
            "Глава пересматривает курс"
        } else if self.station_ore < 10 {
            "Ждёт руду"
        } else {
            "Готовит плавку"
        }
    }

    pub fn ship_status(&self) -> String {
        match self.phase {
            Phase::Waiting if !self.governance.ore_requested => "Нет заявки".into(),
            Phase::Waiting if self.deposit == 0 && self.belt_ore < SHIPMENT => {
                "Залежи исчерпаны".into()
            }
            Phase::Waiting => format!("Ждёт руду — {} из {SHIPMENT}", self.belt_ore.min(SHIPMENT)),
            Phase::Relocating => "Летит за рудой к Марсу".into(),
            Phase::Loading if self.fuel_order => "Загружает топливо".into(),
            Phase::Loading => "Загружает руду".into(),
            Phase::Outbound if self.fuel_cargo > 0 => {
                format!("В пути — {} топлива", self.fuel_cargo)
            }
            Phase::Outbound => format!("В пути — {} руды", self.cargo),
            Phase::Unloading if self.fuel_order => "Разгружает топливо".into(),
            Phase::Unloading => "Разгружает руду".into(),
            Phase::Returning => "Возвращается в пояс".into(),
            Phase::NoFuelAtBelt | Phase::NoFuelAtEarth => "Нет топлива на рейс".into(),
        }
    }

    pub fn step(&mut self, delta: f64) -> Vec<Event> {
        self.migrate_fleet();
        self.tick += 1;
        self.pending += delta;
        let mut events = Vec::new();
        while self.pending >= QUANTUM {
            self.pending -= QUANTUM;
            self.seconds += QUANTUM;
            self.plan(&mut events);
            self.run_facilities(&mut events);
            self.move_ship(&mut events);
            self.migrate_fleet();
            if let Some(mut second) = self.second_freighter.take() {
                second.advance(self, &mut events);
                self.second_freighter = Some(second);
            }
            self.construct(&mut events);
            self.migrate_fleet();
            self.run_conflict(&mut events);
            self.expand(&mut events);
            self.plan_builds(&mut events);
        }
        events
    }

    fn plan(&mut self, events: &mut Vec<Event>) {
        if let Some(reason) = self.governance.review(self.station_fuel, QUANTUM) {
            events.push(decision("policy_changed", "Глава фракции", reason));
        }
        // A dispatched order owns its shipment until arrival.
        if self.delivery_active() {
            return;
        }
        let target = self.governance.policy.ore_target();
        let reserved = u32::from(self.batch_active());
        let expected_stock = self.station_ore.saturating_sub(10 * reserved);
        let requested = self.station_fuel > self.governance.leader.reserve() + reserved
            && expected_stock < target;
        if requested != self.governance.ore_requested {
            self.governance.ore_requested = requested;
            if requested {
                events.push(decision("ore_requested", "Снабженец",
                    format!("Ожидаемый запас руды {expected_stock} при цели {target}. Заказано {SHIPMENT}.")));
            } else {
                events.push(decision(
                    "ore_cancelled",
                    "Снабженец",
                    self.delivery_status().into(),
                ));
            }
        }
    }

    fn run_facilities(&mut self, events: &mut Vec<Event>) {
        if self.governance.ore_requested
            && (!self.delivery_active() || self.second_freighter.is_some()) {
            let mars = self.prefer_mars();
            self.mining_elapsed += QUANTUM;
            if self.mining_elapsed >= MINE_INTERVAL {
                self.mining_elapsed = 0.0;
                let (stock, quantity, location) = if mars {
                    let quantity = 10
                        .min(SHIPMENT.saturating_sub(self.construction.mars_ore))
                        .min(MARS_ORE - self.construction.mars_extracted);
                    self.construction.mars_extracted += quantity;
                    (&mut self.construction.mars_ore, quantity, MARS_SITE)
                } else {
                    let quantity = 10
                        .min(SHIPMENT.saturating_sub(self.belt_ore))
                        .min(self.deposit);
                    self.deposit -= quantity;
                    (&mut self.belt_ore, quantity, BELT)
                };
                *stock += quantity;
                if quantity > 0 {
                    events.push(event(
                        "ore_extracted",
                        "ore",
                        location,
                        quantity,
                        *stock,
                        None,
                    ));
                }
            }
        }
        if self.batch_active() || (self.has_ore_use() && self.station_ore >= 10) {
            if !self.batch_active() {
                events.push(decision(
                    "smelt_started",
                    "Промышленник",
                    "Под партию выделены 10 руды и 1 топливо.".into(),
                ));
            }
            self.smelting_elapsed += QUANTUM;
            if self.smelting_elapsed >= self.smelting_cycle().1 {
                self.smelting_elapsed = 0.0;
                self.station_ore -= 10;
                self.station_fuel -= 1;
                self.metal += 8;
                let mut completed = event("metal_smelted", "metals", EARTH, 8, self.metal, None);
                completed.actor = Some("Промышленник");
                events.push(completed);
            }
        }
    }

    pub fn freight_duration(&self) -> f64 {
        match self.phase {
            Phase::Outbound | Phase::Relocating if self.route_duration > 0.0 => self.route_duration,
            Phase::Returning if self.return_duration > 0.0 => self.return_duration,
            _ => self.phase.duration(),
        }
    }

    fn prefer_mars(&self) -> bool {
        self.construction.mars == MarsProject::Ready
            && (self.construction.mars_ore + MARS_ORE - self.construction.mars_extracted
                >= SHIPMENT)
            && (self.conflict.lost_ore > 0
                || self.belt_ore + self.deposit < SHIPMENT
                || crate::view::route_distance(self, MARS_SITE, EARTH)
                    < crate::view::route_distance(self, BELT, EARTH))
    }

    fn move_ship(&mut self, events: &mut Vec<Event>) {
        if self.phase == Phase::Waiting {
            self.mars_route = false;
            let back = leg(self, EARTH, BELT);
            self.fuel_order = self.station_fuel <= self.governance.leader.reserve() + 12
                && self.belt_fuel >= FUEL_SHIPMENT + 2 * FLIGHT_FUEL;
            let belt_ready = self.belt_ore >= SHIPMENT;
            let mars_ready = self.prefer_mars() && self.construction.mars_ore >= SHIPMENT;
            if !self.fuel_order && !(self.governance.ore_requested && (mars_ready || belt_ready)) {
                return;
            }
            self.mars_route = !self.fuel_order && mars_ready;
            let to_mars = if self.mars_route {
                leg(self, BELT, MARS_SITE)
            } else {
                (0.0, 0)
            };
            let outbound = leg(self, if self.mars_route { MARS_SITE } else { BELT }, EARTH);
            let required = to_mars.1 + outbound.1 + back.1;
            let stock =
                self.belt_fuel
                    .saturating_sub(if self.fuel_order { FUEL_SHIPMENT } else { 0 });
            let refill = required.saturating_sub(self.fuel).min(stock);
            if self.fuel + refill < required {
                self.phase = Phase::NoFuelAtBelt;
                return;
            }
            self.belt_fuel -= refill;
            self.fuel += refill;
            self.fuel -= to_mars.1;
            self.route_duration = if self.mars_route {
                to_mars.0
            } else {
                outbound.0
            };
            self.return_duration = back.0;
            self.return_fuel = back.1;
            self.outbound_plan = outbound;
            self.elapsed = 0.0;
            self.phase = if self.mars_route {
                Phase::Relocating
            } else {
                Phase::Loading
            };
            return;
        }
        if matches!(self.phase, Phase::NoFuelAtBelt | Phase::NoFuelAtEarth) {
            return;
        }
        self.elapsed += QUANTUM;
        if self.elapsed < self.freight_duration() {
            return;
        }
        self.elapsed = 0.0;
        self.phase = match self.phase {
            Phase::Loading => {
                // With independent freighters, stock may have been taken by
                // another vessel since this loading operation started. Never
                // allow unsigned underflow or a duplicated cargo pickup.
                let available = if self.mars_route {
                    self.construction.mars_ore >= SHIPMENT
                } else {
                    self.belt_ore >= SHIPMENT
                };
                if (self.fuel_order && self.belt_fuel < FUEL_SHIPMENT)
                    || (!self.fuel_order && !available)
                {
                    self.phase = Phase::Waiting;
                    return;
                }
                let cost = if self.outbound_plan.1 > 0 {
                    self.route_duration = self.outbound_plan.0;
                    self.outbound_plan.1
                } else {
                    let refill = (2 * FLIGHT_FUEL)
                        .saturating_sub(self.fuel)
                        .min(self.belt_fuel);
                    self.fuel += refill;
                    self.belt_fuel -= refill;
                    if self.fuel < 2 * FLIGHT_FUEL {
                        self.phase = Phase::NoFuelAtBelt;
                        return;
                    }
                    FLIGHT_FUEL
                };
                self.fuel -= cost;
                if self.fuel_order {
                    self.belt_fuel -= FUEL_SHIPMENT;
                    self.fuel_cargo = FUEL_SHIPMENT;
                    events.push(event(
                        "fuel_loaded",
                        "fuel",
                        BELT,
                        FUEL_SHIPMENT,
                        self.belt_fuel,
                        Some(self.freighter_name()),
                    ));
                    self.phase = Phase::Outbound;
                    return;
                }
                let (stock, source) = if self.mars_route {
                    (&mut self.construction.mars_ore, MARS_SITE)
                } else {
                    (&mut self.belt_ore, BELT)
                };
                *stock -= SHIPMENT;
                let remaining = *stock;
                self.cargo = SHIPMENT;
                events.push(event(
                    "cargo_loaded",
                    "ore",
                    source,
                    SHIPMENT,
                    remaining,
                    Some(self.freighter_name()),
                ));
                Phase::Outbound
            }
            Phase::Relocating => Phase::Loading,
            Phase::Outbound => Phase::Unloading,
            Phase::Unloading => {
                if self.fuel_order {
                    self.station_fuel += std::mem::take(&mut self.fuel_cargo);
                    self.fuel_order = false;
                    events.push(event(
                        "fuel_unloaded",
                        "fuel",
                        EARTH,
                        FUEL_SHIPMENT,
                        self.station_fuel,
                        Some(self.freighter_name()),
                    ));
                } else {
                    self.station_ore += self.cargo;
                    events.push(event(
                        "cargo_unloaded",
                        "ore",
                        EARTH,
                        self.cargo,
                        self.station_ore,
                        Some(self.freighter_name()),
                    ));
                    self.cargo = 0;
                    self.governance.ore_requested = false;
                }
                // Older saves can contain a freighter without return fuel in transit.
                let available = self
                    .station_fuel
                    .saturating_sub(u32::from(self.batch_active()));
                let cost = if self.return_fuel > 0 {
                    self.return_fuel
                } else {
                    FLIGHT_FUEL
                };
                let refill = cost.saturating_sub(self.fuel).min(available);
                self.fuel += refill;
                self.station_fuel -= refill;
                if self.fuel >= cost {
                    self.fuel -= cost;
                    Phase::Returning
                } else {
                    Phase::NoFuelAtEarth
                }
            }
            Phase::Returning => {
                self.mars_route = false;
                self.outbound_plan = (0.0, 0);
                // Do not rotate the two ships through the same global
                // Phase/fuel/cargo ledger. The secondary now acts independently.
                if self.construction.phase == Project::Complete {
                    self.migrate_fleet();
                }
                Phase::Waiting
            }
            _ => unreachable!(),
        };
    }
    pub fn metal_capacity(&self) -> u32 {
        if self.genesis_program.has(Kind::Warehouse) {
            140
        } else {
            METAL_CAPACITY
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
                        && self.deposit < SEED_ORE - SHIPMENT
                        && self.station_ore < 30 =>
                {
                    22.0
                }
                Kind::Mine if legacy_mars == MarsProject::Proposed => {
                    let pressure = self.conflict.lost_ore.min(60) as f64 * 0.8
                        + if self.deposit < 140 { 26.0 } else { 0.0 };
                    if site == BuildSite::Belt {
                        pressure * 0.6
                    } else {
                        pressure
                    }
                }
                Kind::Warehouse
                    if site == BuildSite::Earth
                        && self.metal + 8 > self.metal_capacity()
                        && self.station_ore >= 10 =>
                {
                    14.0
                }
                Kind::Smelter
                    if site == BuildSite::Earth
                        && self.station_ore >= 40
                        && self.metal + 16 < self.metal_capacity() =>
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
                self.metal,
                self.station_fuel.saturating_sub(
                    self.governance.leader.reserve() + u32::from(self.batch_active()),
                ),
                need,
                |site| crate::view::build_distance(self, false, site),
            );
            if let Some(work) = work {
                self.metal -= work.choice.kind.spec().metal;
                self.station_fuel -= work.fuel;
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
        let raid_distance = crate::view::route_distance(self, PIRATE_BASE, BELT);
        let raid_cost = (raid_distance * 0.42).ceil().clamp(2.0, 6.0) as u32;
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
            if self.phase == Phase::Outbound
                && self.elapsed == 0.0
                && self.cargo >= 10
                && !self.mars_route
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
                if self.phase == Phase::Outbound && self.cargo >= 10 {
                    self.cargo -= 10;
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
                    && self.metal >= PATROL_METAL =>
            {
                self.metal -= PATROL_METAL;
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
                if self.metal >= PATROL_METAL
                    && self.station_fuel
                        >= self.governance.leader.reserve() + PATROL_SEED_FUEL + 1 =>
            {
                self.metal -= PATROL_METAL;
                self.station_fuel -= PATROL_SEED_FUEL;
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
                        let available = self.station_fuel.saturating_sub(
                            self.governance.leader.reserve()
                                + u32::from(self.smelting_elapsed > 0.0),
                        );
                        let quantity = (PATROL_SEED_FUEL - war.patrol_fuel).min(available);
                        if quantity > 0 {
                            self.station_fuel -= quantity;
                            war.patrol_fuel += quantity;
                            events.push(event(
                                "refueled",
                                "fuel",
                                EARTH,
                                quantity,
                                self.station_fuel,
                                Some("Патруль-001"),
                            ));
                        }
                    }
                    let maintenance =
                        war.patrol_sorties > 0 && war.patrol_sorties.is_multiple_of(2);
                    if war.patrol_fuel >= 2 && (!maintenance || self.metal >= 4) {
                        if maintenance {
                            self.metal -= 4;
                            events.push(event(
                                "patrol_maintenance",
                                "metals",
                                EARTH,
                                4,
                                self.metal,
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

    /// Upgrade 0.8.x saves without deleting the stored world or cargo.
    /// If old Freighter-002 is flying, wait until it returns before
    /// splitting the two ledgers: an in-flight state cannot be safely
    /// transferred to an unrelated position.
    pub fn migrate_fleet(&mut self) {
        if self.second_freighter.is_some()
            || self.construction.phase != Project::Complete
        { return; }
        if self.construction.active_second {
            if self.phase != Phase::Waiting { return; }
            self.rotate_freighters();
        }
        self.second_freighter = Some(Freighter::new(self.construction.parked_fuel));
        self.construction.parked_fuel = 0;
    }

    pub fn freighter_name(&self) -> &'static str {
        if self.construction.active_second {
            "Грузовой-002"
        } else {
            SHIP
        }
    }

    fn rotate_freighters(&mut self) {
        self.construction.active_second = !self.construction.active_second;
        std::mem::swap(&mut self.fuel, &mut self.construction.parked_fuel);
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
        location,
        quantity,
        stock,
        ship_name,
        actor: None,
        reason: None,
    }
}

fn decision(kind: &'static str, actor: &'static str, reason: String) -> Event {
    let mut entry = event(kind, "ore", EARTH, 0, 0, None);
    entry.actor = Some(actor);
    entry.reason = Some(reason);
    entry
}
