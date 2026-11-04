use serde::{Deserialize, Serialize};

pub const SHIPMENT: u32 = 50;
pub const TANK: u32 = 100;
pub const BELT: &str = "belt-outpost";
pub const EARTH: &str = "earth-station";
pub const SHIP: &str = "Грузовой-001";
const FLIGHT_FUEL: u32 = 8;

#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Phase {
    #[default]
    Mining,
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
            Self::Mining => 4.0,
            Self::Loading | Self::Unloading => 3.0,
            Self::Outbound | Self::Returning => 16.0,
            Self::NoFuelAtBelt | Self::NoFuelAtEarth => f64::INFINITY,
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
            phase: Phase::Mining,
            elapsed: 0.0,
            seconds: 0.0,
            tick: 0,
            belt_ore: 0,
            station_ore: 0,
            cargo: 0,
            fuel: TANK,
            belt_fuel: 200,
            station_fuel: 200,
        }
    }
}

impl Sim {
    pub fn valid(&self) -> bool {
        let has_cargo = matches!(self.phase, Phase::Outbound | Phase::Unloading);
        let has_stock = matches!(self.phase, Phase::Loading | Phase::NoFuelAtBelt);
        self.seconds.is_finite()
            && self.seconds >= 0.0
            && (0.0..self.phase.duration()).contains(&self.elapsed)
            && self.cargo == if has_cargo { SHIPMENT } else { 0 }
            && self.belt_ore == if has_stock { SHIPMENT } else { 0 }
            && self.fuel <= TANK
            && self.station_fuel <= 200
            && self.belt_fuel <= 200
            && self.station_ore <= 5_000
            && self.tick < u64::MAX
    }

    pub fn step(&mut self, delta: f64) -> Vec<Event> {
        self.tick += 1;
        self.seconds += delta;
        let mut left = delta;
        let mut events = Vec::new();
        while !matches!(self.phase, Phase::NoFuelAtBelt | Phase::NoFuelAtEarth) {
            let span = self.phase.duration() - self.elapsed;
            if left < span {
                self.elapsed += left;
                break;
            }
            left -= span;
            self.elapsed = 0.0;
            self.phase = match self.phase {
                Phase::Mining => {
                    self.belt_ore += SHIPMENT;
                    events.push(Event {
                        kind: "ore_extracted",
                        commodity: "ore",
                        location: BELT,
                        quantity: SHIPMENT,
                        stock: self.belt_ore,
                        ship_name: None,
                    });
                    Phase::Loading
                }
                Phase::Loading if spend_fuel(&mut self.fuel, &mut self.belt_fuel) => {
                    self.belt_ore -= SHIPMENT;
                    self.cargo = SHIPMENT;
                    events.push(Event {
                        kind: "cargo_loaded",
                        commodity: "ore",
                        location: BELT,
                        quantity: SHIPMENT,
                        stock: self.belt_ore,
                        ship_name: Some(SHIP),
                    });
                    Phase::Outbound
                }
                Phase::Outbound => Phase::Unloading,
                Phase::Unloading => {
                    self.station_ore += self.cargo;
                    events.push(Event {
                        kind: "cargo_unloaded",
                        commodity: "ore",
                        location: EARTH,
                        quantity: self.cargo,
                        stock: self.station_ore,
                        ship_name: Some(SHIP),
                    });
                    self.cargo = 0;
                    if spend_fuel(&mut self.fuel, &mut self.station_fuel) {
                        Phase::Returning
                    } else {
                        Phase::NoFuelAtEarth
                    }
                }
                Phase::Returning => Phase::Mining,
                Phase::Loading => Phase::NoFuelAtBelt,
                Phase::NoFuelAtBelt | Phase::NoFuelAtEarth => unreachable!(),
            };
        }
        events
    }
}

fn spend_fuel(tank: &mut u32, reserve: &mut u32) -> bool {
    if *tank < FLIGHT_FUEL {
        let refill = (TANK - *tank).min(*reserve);
        *tank += refill;
        *reserve -= refill;
    }
    if *tank < FLIGHT_FUEL {
        return false;
    }
    *tank -= FLIGHT_FUEL;
    true
}
