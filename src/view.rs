use crate::sim::{BELT, EARTH, Event, Phase, SHIP, Sim, TANK};
use serde_json::{Value, json};
use std::f64::consts::TAU;

const FACTION: &str = "genesis";

#[derive(Clone, Copy)]
struct Point {
    x: f64,
    y: f64,
}

fn orbit(radius: f64, angle: f64) -> Point {
    Point {
        x: radius * angle.cos(),
        y: radius * angle.sin(),
    }
}

fn location(parent: Point, angle: f64) -> Point {
    let offset = orbit(0.15, angle);
    Point {
        x: parent.x + offset.x,
        y: parent.y + offset.y,
    }
}

fn interpolate(a: Point, b: Point, progress: f64) -> Point {
    Point {
        x: a.x + (b.x - a.x) * progress,
        y: a.y + (b.y - a.y) * progress,
    }
}

struct Scene {
    earth: Point,
    belt: Point,
    station: Point,
    rig: Point,
    ship: Point,
}

impl Scene {
    fn at(sim: &Sim) -> Self {
        let earth = orbit(1.0, TAU * sim.seconds / 365.0);
        let belt = orbit(2.7, 2.1 + TAU * sim.seconds / 1680.0);
        let station = location(earth, 0.4 + TAU * sim.seconds / 90.0);
        let rig = location(belt, 2.0 + TAU * sim.seconds / 140.0);
        let progress = sim.elapsed / sim.phase.duration();
        let ship = match sim.phase {
            Phase::Outbound => interpolate(rig, station, progress),
            Phase::Returning => interpolate(station, rig, progress),
            Phase::Unloading => station,
            Phase::NoFuelAtEarth => station,
            _ => rig,
        };
        Self {
            earth,
            belt,
            station,
            rig,
            ship,
        }
    }
}

fn ship(sim: &Sim, scene: &Scene) -> Value {
    let (location, transit) = match sim.phase {
        Phase::Outbound => (None, Some((BELT, EARTH))),
        Phase::Returning => (None, Some((EARTH, BELT))),
        Phase::Unloading => (Some(EARTH), None),
        Phase::NoFuelAtEarth => (Some(EARTH), None),
        _ => (Some(BELT), None),
    };
    json!({
        "id": "freighter-1", "name": SHIP, "class": "freighter", "faction_id": FACTION,
        "docked": transit.is_none(), "location": location, "fuel": sim.fuel, "fuel_capacity": TANK,
        "status_label": if matches!(sim.phase, Phase::NoFuelAtBelt | Phase::NoFuelAtEarth) { Some("Нет топлива") } else { None },
        "position": {"x": scene.ship.x, "y": scene.ship.y}, "cargo": {"ore": sim.cargo},
        "transit": transit.map(|(from, to)| json!({
            "from": from, "to": to, "distance_travelled": sim.elapsed, "distance_total": sim.phase.duration(),
        }))
    })
}

fn markets(sim: &Sim) -> Value {
    json!([
        {"id": BELT, "facility_location": BELT, "supply": {"ore": sim.belt_ore}},
        {"id": EARTH, "facility_location": EARTH, "supply": {"ore": sim.station_ore}},
    ])
}

fn position(id: &str, point: Point) -> Value {
    json!({"id": id, "x": point.x, "y": point.y})
}

pub fn report(sim: &Sim, running: bool, speed: f64) -> Value {
    let scene = Scene::at(sim);
    json!({
        "tick": sim.tick, "running": running, "world_speed": speed, "genesis_ore_loop": true,
        "systems": [{"id": "sol", "name": "Sol", "offset_x": 0, "offset_y": 0, "bodies": [
            {"id": "earth", "name": "Земля", "type": "planet", "orbit_radius": 1.0,
             "x": scene.earth.x, "y": scene.earth.y, "controlling_faction": FACTION},
            {"id": "belt", "name": "Пояс астероидов", "type": "belt", "orbit_radius": 2.7,
             "x": scene.belt.x, "y": scene.belt.y, "controlling_faction": FACTION},
        ]}],
        "facilities": [
            {"id": EARTH, "name": "Станция Земли", "type": "station", "location": EARTH, "body_id": "earth",
             "x": scene.station.x, "y": scene.station.y, "faction_id": FACTION, "reserves": {"fuel": sim.station_fuel}},
            {"id": BELT, "name": "Добывающая установка", "type": "mining_rig", "location": BELT, "body_id": "belt",
             "x": scene.rig.x, "y": scene.rig.y, "faction_id": FACTION, "reserves": {"fuel": sim.belt_fuel}},
        ],
        "ships": [ship(sim, &scene)], "markets": markets(sim),
        "factions": [{"id": FACTION, "name": "Genesis", "colors": {"primary": "#6fb6d9"}}],
    })
}

pub fn update(sim: &Sim, events: &[Event]) -> Value {
    let scene = Scene::at(sim);
    json!({
        "type": "genesis_update", "tick": sim.tick, "events": events,
        "entities": [
            position("earth", scene.earth), position("belt", scene.belt),
            position(EARTH, scene.station), position(BELT, scene.rig), position("freighter-1", scene.ship),
        ],
        "ships": [ship(sim, &scene)], "markets": markets(sim),
        "reserves": { (EARTH): sim.station_fuel, (BELT): sim.belt_fuel },
    })
}
