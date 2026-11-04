use crate::conflict::{
    Conflict, PATROL_METAL, PATROL_SEED_FUEL, PIRATE_BASE, PIRATE_SEED_METAL, Patrol,
};
use crate::construction::{COMMISSION_FUEL, Construction, Project, SHIP_METAL, YARD_METAL};
use crate::governance::Governance;
use serde::{Deserialize, Serialize};

pub const SHIPMENT: u32 = 50;
pub const TANK: u32 = 100;
pub const BELT: &str = "belt-outpost";
pub const EARTH: &str = "earth-station";
pub const SHIP: &str = "Грузовой-001";
const FLIGHT_FUEL: u32 = 8;
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
            Self::Outbound | Self::Returning => 16.0,
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
    #[serde(default = "seed_ore")]
    pub deposit: u32,
    #[serde(default)]
    pub conflict: Conflict,
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
            fuel: TANK,
            belt_fuel: 200,
            station_fuel: 200,
            metal: 0,
            mining_elapsed: 0.0,
            smelting_elapsed: 0.0,
            pending: 0.0,
            governance: Governance::default(),
            construction: Construction::default(),
            deposit: SEED_ORE,
            conflict: Conflict::default(),
        }
    }
}

impl Sim {
    pub fn valid(&self) -> bool {
        let has_cargo = matches!(self.phase, Phase::Outbound | Phase::Unloading);
        self.seconds.is_finite()
            && self.seconds >= 0.0
            && (0.0..self.phase.duration()).contains(&self.elapsed)
            && (if has_cargo {
                (SHIPMENT - 10..=SHIPMENT).contains(&self.cargo)
            } else {
                self.cargo == 0
            })
            && self.belt_ore <= BELT_CAPACITY
            && (self.phase != Phase::Loading || self.belt_ore >= SHIPMENT)
            && self.fuel <= TANK
            && self.station_fuel <= 200
            && self.belt_fuel <= 200
            && self.station_ore <= 5_000
            && self.metal <= METAL_CAPACITY
            && (0.0..MINE_INTERVAL).contains(&self.mining_elapsed)
            && (0.0..SMELT_INTERVAL).contains(&self.smelting_elapsed)
            && (!self.batch_active()
                || (self.station_ore >= 10
                    && self.station_fuel > 0
                    && self.metal + 8 <= METAL_CAPACITY))
            && (0.0..QUANTUM).contains(&self.pending)
            && self.conflict.raider_cargo <= 10
            && self.conflict.patrol_fuel <= PATROL_SEED_FUEL
            && self.deposit <= SEED_ORE
            && self.construction.parked_fuel <= TANK
            && (0.0..self.construction.duration()).contains(&self.construction.elapsed)
            && (!self.construction.active_second || self.construction.phase == Project::Complete)
            && self.tick < u64::MAX
    }

    pub fn delivery_active(&self) -> bool {
        matches!(
            self.phase,
            Phase::Loading | Phase::Outbound | Phase::Unloading
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
        self.metal + 8 <= METAL_CAPACITY && self.station_fuel > self.governance.leader.reserve()
    }

    pub fn batch_active(&self) -> bool {
        self.smelting_elapsed > 0.0
    }

    pub fn smelting_status(&self) -> &'static str {
        if self.batch_active() {
            "Плавит руду"
        } else if self.metal + 8 > METAL_CAPACITY {
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
            Phase::Loading => "Загружает руду".into(),
            Phase::Outbound => format!("В пути — {} руды", self.cargo),
            Phase::Unloading => "Разгружает руду".into(),
            Phase::Returning => "Возвращается в пояс".into(),
            Phase::NoFuelAtBelt | Phase::NoFuelAtEarth => "Нет топлива на рейс".into(),
        }
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
            self.move_ship(&mut events);
            self.construct(&mut events);
            self.run_conflict(&mut events);
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
        let requested = self.metal + 8 * (1 + reserved) <= METAL_CAPACITY
            && self.station_fuel > self.governance.leader.reserve() + reserved
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
            && !self.delivery_active()
            && self.belt_ore < SHIPMENT
            && self.deposit > 0
        {
            self.mining_elapsed += QUANTUM;
            if self.mining_elapsed >= MINE_INTERVAL {
                self.mining_elapsed = 0.0;
                let quantity = 10.min(BELT_CAPACITY - self.belt_ore).min(self.deposit);
                self.deposit -= quantity;
                self.belt_ore += quantity;
                events.push(event(
                    "ore_extracted",
                    "ore",
                    BELT,
                    quantity,
                    self.belt_ore,
                    None,
                ));
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
            if self.smelting_elapsed >= SMELT_INTERVAL {
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

    fn move_ship(&mut self, events: &mut Vec<Event>) {
        if self.phase == Phase::Waiting {
            if self.governance.ore_requested && self.belt_ore >= SHIPMENT {
                self.phase = if self.fuel + self.belt_fuel >= FLIGHT_FUEL * 2 {
                    Phase::Loading
                } else {
                    Phase::NoFuelAtBelt
                };
                self.elapsed = 0.0;
            }
            return;
        }
        if matches!(self.phase, Phase::NoFuelAtBelt | Phase::NoFuelAtEarth) {
            return;
        }
        self.elapsed += QUANTUM;
        if self.elapsed < self.phase.duration() {
            return;
        }
        self.elapsed = 0.0;
        self.phase = match self.phase {
            Phase::Loading => {
                let refill = (2 * FLIGHT_FUEL)
                    .saturating_sub(self.fuel)
                    .min(self.belt_fuel);
                self.fuel += refill;
                self.belt_fuel -= refill;
                if self.fuel < 2 * FLIGHT_FUEL {
                    self.phase = Phase::NoFuelAtBelt;
                    return;
                }
                self.fuel -= FLIGHT_FUEL;
                self.belt_ore -= SHIPMENT;
                self.cargo = SHIPMENT;
                events.push(event(
                    "cargo_loaded",
                    "ore",
                    BELT,
                    SHIPMENT,
                    self.belt_ore,
                    Some(self.freighter_name()),
                ));
                Phase::Outbound
            }
            Phase::Outbound => Phase::Unloading,
            Phase::Unloading => {
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
                // Older saves can contain a freighter without return fuel in transit.
                let available = self
                    .station_fuel
                    .saturating_sub(u32::from(self.batch_active()));
                let refill = FLIGHT_FUEL.saturating_sub(self.fuel).min(available);
                self.fuel += refill;
                self.station_fuel -= refill;
                if self.fuel >= FLIGHT_FUEL {
                    self.fuel -= FLIGHT_FUEL;
                    Phase::Returning
                } else {
                    Phase::NoFuelAtEarth
                }
            }
            Phase::Returning => {
                if self.construction.phase == Project::Complete {
                    self.rotate_freighters();
                }
                Phase::Waiting
            }
            _ => unreachable!(),
        };
    }
    fn run_conflict(&mut self, events: &mut Vec<Event>) {
        let threat_seen = self.conflict.pirate_loot > 0 || self.conflict.raider_cargo > 0;
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
            if war.raider_return >= 6.0 {
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
        if self.phase != Phase::Outbound {
            war.patrol_home_earth |= war.escorted;
            war.escorted = false;
            war.intercepted = false;
        } else {
            if self.elapsed == 0.0 && war.patrol == Patrol::Ready && war.patrol_fuel >= 2 {
                war.patrol_fuel -= 2;
                war.escorted = true;
            }
            if self.elapsed >= 8.0
                && !war.intercepted
                && war.base_ready
                && war.raider_fuel >= 2
                && war.raider_return == 0.0
            {
                war.intercepted = true;
                war.raider_fuel -= 2;
                war.raider_return = QUANTUM;
                if war.escorted {
                    events.push(decision(
                        "raid_deflected",
                        "Патруль-001",
                        "Сопровождение сорвало перехват.".into(),
                    ));
                } else {
                    self.cargo -= 10;
                    war.raider_cargo = 10;
                    events.push(event(
                        "raid_stolen",
                        "ore",
                        PIRATE_BASE,
                        10,
                        self.cargo,
                        None,
                    ));
                }
            }
        }
        match war.patrol {
            Patrol::None
                if threat_seen
                    && self.construction.phase == Project::Complete
                    && self.metal >= PATROL_METAL =>
            {
                self.metal -= PATROL_METAL;
                war.patrol = Patrol::Delivering;
                events.push(decision(
                    "patrol_order",
                    "Глава фракции",
                    format!("После потери груза выделено {PATROL_METAL} металла на патруль."),
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
                        "Патруль-001 готов к сопровождению.".into(),
                    ));
                }
            }
            _ => {}
        }
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
            Project::WaitingMaterials => {
                if self.metal >= YARD_METAL + SHIP_METAL {
                    self.metal -= YARD_METAL + SHIP_METAL;
                    self.construction.phase = Project::Hauling;
                    events.push(decision(
                        "yard_dispatched",
                        "Строитель-001",
                        format!("Загрузил металл со станции Земли: {YARD_METAL} для верфи и {SHIP_METAL} для корпуса."),
                    ));
                }
                return;
            }
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
                if self.phase == Phase::Waiting {
                    self.rotate_freighters();
                }
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

fn event(
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
