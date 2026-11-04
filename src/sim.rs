use crate::conflict::{
    Conflict, PATROL_DURATION, PATROL_METAL, PATROL_SEED_FUEL, PIRATE_BASE, PIRATE_SEED_METAL,
    Patrol, RAID_APPROACH, RAID_RETURN,
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
            deposit: SEED_ORE,
            conflict: Conflict {
                pirate_fuel_stock: 18,
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
            && (0.0..self.phase.duration()).contains(&self.elapsed)
            && (if has_cargo {
                (self.fuel_cargo == FUEL_SHIPMENT && self.cargo == 0 && self.fuel_order)
                    || (self.fuel_cargo == 0 && (SHIPMENT - 10..=SHIPMENT).contains(&self.cargo))
            } else {
                self.cargo == 0 && self.fuel_cargo == 0
            })
            && self.belt_ore <= BELT_CAPACITY
            && (self.phase != Phase::Loading || self.fuel_order || self.belt_ore >= SHIPMENT)
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
            && (0.0..RAID_APPROACH).contains(&self.conflict.raid_elapsed)
            && (0.0..RAID_RETURN).contains(&self.conflict.raider_return)
            && (0.0..PATROL_DURATION).contains(&self.conflict.patrol_cycle)
            && (0.0..=1.0).contains(&self.conflict.retreat_from)
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
            self.fuel_order = self.station_fuel <= self.governance.leader.reserve() + 12
                && self.belt_fuel >= FUEL_SHIPMENT + 2 * FLIGHT_FUEL;
            if self.fuel_order || (self.governance.ore_requested && self.belt_ore >= SHIPMENT) {
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
        let threat_seen = self.conflict.lost_ore > 0
            || self.conflict.pirate_loot > 0
            || self.conflict.raider_cargo > 0;
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
            if war.raider_return >= RAID_RETURN {
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
            if war.raider_damaged
                && war.pirate_metal < 2
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
            if war.raider_damaged && war.pirate_metal >= 2 {
                war.pirate_metal -= 2;
                war.raider_damaged = false;
                events.push(decision(
                    "raider_repaired",
                    "Пираты",
                    "Рейдер отремонтирован трофейным металлом.".into(),
                ));
            }
            if war.raider_fuel < 2 && war.pirate_fuel_stock > 0 {
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
                && !war.raider_damaged
                && war.raider_fuel >= 2
            {
                war.raider_fuel -= 2;
                war.raid_elapsed = QUANTUM;
                war.contact = 0.0;
            }
        }
        if war.raid_elapsed > 0.0 {
            war.raid_elapsed += QUANTUM;
            if war.raid_elapsed >= 5.0 && war.near_intercept() {
                war.contact += QUANTUM;
            }
            if war.contact >= 1.25 {
                war.retreat_from = (war.raid_elapsed / RAID_APPROACH).min(1.0);
                war.raid_elapsed = 0.0;
                war.raider_return = QUANTUM;
                war.raider_damaged = true;
                war.intercepted_raids += 1;
                events.push(decision(
                    "raid_deflected",
                    "Патруль-001",
                    "Рейдер обнаружен в зоне патруля. Перехват завершился до захвата груза.".into(),
                ));
            } else if war.raid_elapsed >= RAID_APPROACH {
                war.retreat_from = (war.raid_elapsed / RAID_APPROACH).min(1.0);
                war.raid_elapsed = 0.0;
                war.raider_return = QUANTUM;
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
