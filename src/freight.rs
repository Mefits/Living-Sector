//! Second freighter: its own persisted state machine and fuel/cargo ledger.
//! Transitional Genesis slice: Freighter-001 still uses Sim's legacy state,
//! Freighter-002 does not borrow/swap that state. Later an agent registry can
//! give *all* ships the same implementation.

use serde::{Deserialize, Serialize};
use crate::sim::{event, leg, Event, Sim, BELT, EARTH, SHIPMENT, TANK};

const FUEL_SHIPMENT: u32 = 24;
const LOADING_SECONDS: f64 = 3.0;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FreightPhase {
    #[default]
    Waiting,
    Loading,
    Outbound,
    Unloading,
    Returning,
    NoFuelAtBelt,
    NoFuelAtEarth,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Freighter {
    pub phase: FreightPhase,
    pub elapsed: f64,
    pub fuel: u32,
    pub cargo: u32,
    pub fuel_cargo: u32,
    pub fuel_order: bool,
    pub outbound_duration: f64,
    pub return_duration: f64,
    pub outbound_cost: u32,
    pub return_cost: u32,
}

impl Default for Freighter {
    fn default() -> Self {
        Self {
            phase: FreightPhase::Waiting, elapsed: 0.0, fuel: 0,
            cargo: 0, fuel_cargo: 0, fuel_order: false,
            outbound_duration: 0.0, return_duration: 0.0,
            outbound_cost: 0, return_cost: 0,
        }
    }
}

impl Freighter {
    pub fn new(fuel: u32) -> Self { Self { fuel, ..Self::default() } }

    pub fn duration(&self) -> f64 {
        match self.phase {
            FreightPhase::Loading | FreightPhase::Unloading => LOADING_SECONDS,
            FreightPhase::Outbound => self.outbound_duration.max(0.25),
            FreightPhase::Returning => self.return_duration.max(0.25),
            _ => f64::INFINITY,
        }
    }

    pub fn valid(&self) -> bool {
        self.elapsed.is_finite() && self.elapsed >= 0.0 &&
            self.elapsed < self.duration() &&
            self.outbound_duration.is_finite() && self.outbound_duration >= 0.0 &&
            self.return_duration.is_finite() && self.return_duration >= 0.0 &&
            self.fuel <= TANK && self.cargo <= SHIPMENT &&
            self.fuel_cargo <= FUEL_SHIPMENT &&
            !(self.cargo > 0 && self.fuel_cargo > 0) &&
            (self.cargo == 0 && self.fuel_cargo == 0 ||
                matches!(self.phase, FreightPhase::Outbound | FreightPhase::Unloading))
    }

    pub fn status(&self) -> String {
        match self.phase {
            FreightPhase::Waiting => "Ожидает задание на доставку".into(),
            FreightPhase::Loading if self.fuel_order => "Загружает топливо".into(),
            FreightPhase::Loading => "Загружает руду".into(),
            FreightPhase::Outbound if self.fuel_cargo > 0 => {
                format!("Везёт {} топлива на станцию", self.fuel_cargo)
            }
            FreightPhase::Outbound => format!("Везёт {} руды на станцию", self.cargo),
            FreightPhase::Unloading => "Разгружается на станции".into(),
            FreightPhase::Returning => "Возвращается к добыче".into(),
            FreightPhase::NoFuelAtBelt => "Ждёт топливо в поясе".into(),
            FreightPhase::NoFuelAtEarth => "Ждёт топливо на станции".into(),
        }
    }

    pub fn advance(&mut self, sim: &mut Sim, events: &mut Vec<Event>) {
        if self.phase == FreightPhase::NoFuelAtBelt {
            self.phase = FreightPhase::Waiting;
        }
        if self.phase == FreightPhase::NoFuelAtEarth {
            let available = sim.station_fuel.saturating_sub(u32::from(sim.batch_active()));
            let refill = self.return_cost.saturating_sub(self.fuel).min(available);
            sim.station_fuel -= refill;
            self.fuel += refill;
            if self.fuel < self.return_cost { return; }
            self.fuel -= self.return_cost;
            self.phase = FreightPhase::Returning;
            self.elapsed = 0.0;
            return;
        }
        if self.phase == FreightPhase::Waiting {
            // A second freighter may accept a different task even while
            // Freighter-001 is executing its own flight.
            let food_for_plant = sim.station_fuel <= sim.governance.leader.reserve() + 12;
            let refuel_job = food_for_plant && sim.belt_fuel >= FUEL_SHIPMENT + 2;
            let ore_job = sim.governance.ore_requested && sim.belt_ore >= SHIPMENT;
            if !refuel_job && !ore_job { return; }
            let (out_time, out_cost) = leg(sim, BELT, EARTH);
            let (back_time, back_cost) = leg(sim, EARTH, BELT);
            let total = out_cost + back_cost;
            let reserve = if refuel_job { FUEL_SHIPMENT } else { 0 };
            let available = sim.belt_fuel.saturating_sub(reserve);
            let add = total.saturating_sub(self.fuel).min(available);
            if self.fuel + add < total {
                self.phase = FreightPhase::NoFuelAtBelt;
                return;
            }
            self.fuel += add;
            sim.belt_fuel -= add;
            self.outbound_duration = out_time;
            self.return_duration = back_time;
            self.outbound_cost = out_cost;
            self.return_cost = back_cost;
            self.fuel_order = refuel_job;
            self.phase = FreightPhase::Loading;
            self.elapsed = 0.0;
            return;
        }

        self.elapsed += 0.25;
        if self.elapsed < self.duration() { return; }
        self.elapsed = 0.0;
        match self.phase {
            FreightPhase::Loading => {
                // Actual pickup occurs once, when loading completes, using
                // the *current* shared stock. Never use an unverified promise.
                if self.fuel_order {
                    if sim.belt_fuel < FUEL_SHIPMENT {
                        self.phase = FreightPhase::Waiting;
                        return;
                    }
                    sim.belt_fuel -= FUEL_SHIPMENT;
                    self.fuel_cargo = FUEL_SHIPMENT;
                    events.push(event("fuel_loaded", "fuel", BELT,
                        FUEL_SHIPMENT, sim.belt_fuel, Some("Грузовой-002")));
                } else {
                    if sim.belt_ore < SHIPMENT {
                        self.phase = FreightPhase::Waiting;
                        return;
                    }
                    sim.belt_ore -= SHIPMENT;
                    self.cargo = SHIPMENT;
                    events.push(event("cargo_loaded", "ore", BELT,
                        SHIPMENT, sim.belt_ore, Some("Грузовой-002")));
                }
                self.fuel -= self.outbound_cost;
                self.phase = FreightPhase::Outbound;
            }
            FreightPhase::Outbound => {
                self.phase = FreightPhase::Unloading;
            }
            FreightPhase::Unloading => {
                if self.fuel_order {
                    sim.station_fuel += self.fuel_cargo;
                    events.push(event("fuel_unloaded", "fuel", EARTH,
                        self.fuel_cargo, sim.station_fuel, Some("Грузовой-002")));
                    self.fuel_cargo = 0;
                } else {
                    sim.station_ore += self.cargo;
                    events.push(event("cargo_unloaded", "ore", EARTH,
                        self.cargo, sim.station_ore, Some("Грузовой-002")));
                    self.cargo = 0;
                    sim.governance.ore_requested = false;
                }
                self.fuel_order = false;
                let available = sim.station_fuel.saturating_sub(u32::from(sim.batch_active()));
                let refill = self.return_cost.saturating_sub(self.fuel).min(available);
                sim.station_fuel -= refill;
                self.fuel += refill;
                if self.fuel >= self.return_cost {
                    self.fuel -= self.return_cost;
                    self.phase = FreightPhase::Returning;
                } else {
                    self.phase = FreightPhase::NoFuelAtEarth;
                }
            }
            FreightPhase::Returning => {
                self.phase = FreightPhase::Waiting;
            }
            FreightPhase::NoFuelAtBelt | FreightPhase::NoFuelAtEarth |
            FreightPhase::Waiting => {}
        }
    }
}
