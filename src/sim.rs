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
        }
    }
}

impl Sim {
    pub fn valid(&self) -> bool {
        let has_cargo = matches!(self.phase, Phase::Outbound | Phase::Unloading);
        self.seconds.is_finite()
            && self.seconds >= 0.0
            && (0.0..self.phase.duration()).contains(&self.elapsed)
            && self.cargo == if has_cargo { SHIPMENT } else { 0 }
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
        if self.governance.ore_requested && !self.delivery_active() && self.belt_ore < SHIPMENT {
            self.mining_elapsed += QUANTUM;
            if self.mining_elapsed >= MINE_INTERVAL {
                self.mining_elapsed = 0.0;
                let quantity = 10.min(BELT_CAPACITY - self.belt_ore);
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
                    Some(SHIP),
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
                    Some(SHIP),
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
            Phase::Returning => Phase::Waiting,
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
