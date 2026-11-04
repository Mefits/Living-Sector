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
const REORDER_BELOW: u32 = 20;
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
}

#[derive(Clone, Copy, Serialize)]
pub struct Event {
    kind: &'static str,
    commodity: &'static str,
    location: &'static str,
    quantity: u32,
    stock: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    ship_name: Option<&'static str>,
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
            && (0.0..QUANTUM).contains(&self.pending)
            && self.tick < u64::MAX
    }

    pub fn delivery_status(&self) -> &'static str {
        if matches!(
            self.phase,
            Phase::Loading | Phase::Outbound | Phase::Unloading
        ) {
            "Выполняется"
        } else if self.needs_ore() {
            "Ожидает доставки"
        } else {
            "Запас достаточный"
        }
    }

    fn needs_ore(&self) -> bool {
        self.station_ore < REORDER_BELOW
    }

    pub fn smelting_status(&self) -> &'static str {
        if self.metal + 8 > METAL_CAPACITY {
            "Склад металла заполнен"
        } else if self.station_ore < 10 {
            "Ждёт руду"
        } else if self.station_fuel == 0 {
            "Ждёт топливо"
        } else {
            "Плавит руду"
        }
    }

    pub fn ship_status(&self) -> String {
        match self.phase {
            Phase::Waiting if !self.needs_ore() => "Нет заявки".into(),
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
            self.run_facilities(&mut events);
            self.move_ship(&mut events);
        }
        events
    }

    fn run_facilities(&mut self, events: &mut Vec<Event>) {
        if self.belt_ore < BELT_CAPACITY {
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
        if self.metal + 8 <= METAL_CAPACITY && self.station_ore >= 10 && self.station_fuel > 0 {
            self.smelting_elapsed += QUANTUM;
            if self.smelting_elapsed >= SMELT_INTERVAL {
                self.smelting_elapsed = 0.0;
                let already_needed_ore = self.needs_ore();
                self.station_ore -= 10;
                self.station_fuel -= 1;
                self.metal += 8;
                events.push(event("metal_smelted", "metals", EARTH, 8, self.metal, None));
                if !already_needed_ore && self.needs_ore() {
                    events.push(event(
                        "ore_requested",
                        "ore",
                        EARTH,
                        SHIPMENT,
                        self.station_ore,
                        None,
                    ));
                }
            }
        }
    }

    fn move_ship(&mut self, events: &mut Vec<Event>) {
        if self.phase == Phase::Waiting {
            if self.needs_ore() && self.belt_ore >= SHIPMENT {
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
                // Older saves can contain a freighter without return fuel in transit.
                let refill = FLIGHT_FUEL.saturating_sub(self.fuel).min(self.station_fuel);
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
    }
}
