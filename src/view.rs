use crate::conflict::{
    PATROL_METAL, PATROL_SEED_FUEL, PIRATE_BASE, Patrol, RAID_APPROACH, RAID_RETURN,
};
use crate::construction::{Project, SHIP_METAL, SITE, YARD_METAL};
use crate::sim::{BELT, EARTH, Event, METAL_CAPACITY, Phase, Sim, TANK};
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
    yard: Point,
    pirate: Point,
    venus: Point,
    mars: Point,
    jupiter: Point,
}

impl Scene {
    fn at(sim: &Sim) -> Self {
        let earth = orbit(1.0, TAU * sim.seconds / 365.0);
        let belt = orbit(2.7, 2.1 + TAU * sim.seconds / 1680.0);
        let station = location(earth, 0.4 + TAU * sim.seconds / 90.0);
        let rig = location(belt, 2.0 + TAU * sim.seconds / 140.0);
        let offset = orbit(0.36, 2.8 + TAU * sim.seconds / 112.0);
        let yard = Point {
            x: earth.x + offset.x,
            y: earth.y + offset.y,
        };
        let venus = orbit(0.72, 1.2 + TAU * sim.seconds / 225.0);
        let mars = orbit(1.52, -0.8 + TAU * sim.seconds / 687.0);
        let jupiter = orbit(5.20, -2.3 + TAU * sim.seconds / 4333.0);
        let pirate = location(jupiter, 0.9 + TAU * sim.seconds / 180.0);
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
            yard,
            pirate,
            venus,
            mars,
            jupiter,
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
        "id": freighter_id(sim.construction.active_second), "name": sim.freighter_name(), "class": "freighter", "faction_id": FACTION,
        "docked": transit.is_none(), "location": location, "fuel": sim.fuel, "fuel_capacity": TANK,
        "status_label": sim.ship_status(),
        "position": {"x": scene.ship.x, "y": scene.ship.y}, "cargo": {"ore": sim.cargo, "fuel": sim.fuel_cargo},
        "transit": transit.map(|(from, to)| json!({
            "from": from, "to": to, "distance_travelled": sim.elapsed, "distance_total": sim.phase.duration(),
        }))
    })
}

fn freighter_id(second: bool) -> &'static str {
    if second { "freighter-2" } else { "freighter-1" }
}

fn ships(sim: &Sim, scene: &Scene) -> Vec<Value> {
    let mut ships = vec![ship(sim, scene)];
    let phase = sim.construction.phase;
    let progress = sim.construction.elapsed / sim.construction.duration();
    let delivering_patrol = sim.conflict.patrol == Patrol::Delivering;
    let builder_route = match phase {
        _ if delivering_patrol => Some((EARTH, SITE, scene.station, scene.yard)),
        Project::Hauling => Some((EARTH, SITE, scene.station, scene.yard)),
        Project::Returning => Some((SITE, EARTH, scene.yard, scene.station)),
        _ => None,
    };
    let builder = builder_route.map_or_else(
        || {
            if phase == Project::Assembling {
                scene.yard
            } else {
                scene.station
            }
        },
        |(_, _, from, to)| {
            interpolate(
                from,
                to,
                if delivering_patrol {
                    sim.conflict.patrol_elapsed / 4.0
                } else {
                    progress
                },
            )
        },
    );
    let builder_at_yard = phase == Project::Assembling
        || matches!(sim.conflict.patrol, Patrol::Building | Patrol::Ready);
    let builder = if builder_route.is_none() && builder_at_yard {
        scene.yard
    } else {
        builder
    };
    ships.push(json!({
        "id": "builder-1", "name": "Строитель-001", "class": "constructor",
        "faction_id": FACTION, "docked": builder_route.is_none(),
        "location": if builder_route.is_some() { None } else if builder_at_yard { Some(SITE) } else { Some(EARTH) },
        "fuel": sim.construction.builder_fuel() + if sim.conflict.patrol == Patrol::None { 4 } else { 0 }, "fuel_capacity": 12,
        "position": position("builder-1", builder),
        "cargo": {
            "metals": if delivering_patrol { PATROL_METAL } else if phase == Project::Hauling { YARD_METAL + SHIP_METAL } else { 0 },
            "fuel": if delivering_patrol { PATROL_SEED_FUEL } else if phase == Project::Hauling { 8 } else { 0 }
        },
        "status_label": if delivering_patrol { "Везёт материалы для патруля" } else { match phase {
            Project::WaitingMaterials => "Ждёт металл",
            Project::Hauling => "Везёт стройматериалы",
            Project::Assembling => "Собирает верфь",
            Project::Returning => "Возвращается на станцию",
            _ => "У причала",
        } },
        "transit": builder_route.map(|(from, to, _, _)| json!({
            "from": from, "to": to, "distance_travelled": if delivering_patrol { sim.conflict.patrol_elapsed } else { sim.construction.elapsed },
            "distance_total": if delivering_patrol { 4.0 } else { sim.construction.duration() },
        })),
    }));
    if matches!(phase, Project::TransferringShip | Project::Complete) {
        let in_transfer = phase == Project::TransferringShip;
        let id = freighter_id(!sim.construction.active_second);
        let point = if in_transfer {
            interpolate(scene.yard, scene.rig, progress)
        } else {
            scene.rig
        };
        ships.push(json!({
            "id": id, "name": if sim.construction.active_second { "Грузовой-001" } else { "Грузовой-002" },
            "class": "freighter", "faction_id": FACTION,
            "docked": !in_transfer, "location": if in_transfer { None } else { Some(BELT) },
            "fuel": sim.construction.parked_fuel, "fuel_capacity": TANK, "position": position(id, point),
            "cargo": {"ore": 0},
            "transit": in_transfer.then(|| json!({
                "from": SITE, "to": BELT, "distance_travelled": sim.construction.elapsed,
                "distance_total": sim.construction.duration(),
            })),
        }));
    }
    let war = &sim.conflict;
    let crossing = interpolate(scene.rig, scene.station, 0.5);
    let chasing = war.raid_elapsed > 0.0;
    let returning = war.raider_return > 0.0;
    let raider_point = if returning {
        interpolate(
            interpolate(scene.pirate, crossing, war.retreat_from),
            scene.pirate,
            war.raider_return / RAID_RETURN,
        )
    } else if chasing {
        interpolate(scene.pirate, crossing, war.raid_elapsed / RAID_APPROACH)
    } else {
        scene.pirate
    };
    ships.push(json!({
        "id": "pirate-builder-1", "name": "Пиратский строитель", "class": "pirate-builder",
        "faction_id": "pirates", "docked": true, "location": PIRATE_BASE,
        "position": position("pirate-builder-1", scene.pirate), "fuel": 0, "fuel_capacity": 0,
        "cargo": {"metals": if !war.base_ready { 16 } else if war.base_progress < 40.0 { 8 } else { 0 }},
        "status_label": if !war.base_ready { "Собирает базу" } else if war.base_progress < 40.0 { "Собирает рейдер" } else { "У причала" },
    }));
    if war.base_progress >= 40.0 {
        ships.push(json!({
            "id": "raider-1", "name": "Пиратский рейдер", "class": "pirate-patrol",
            "faction_id": "pirates", "docked": !(returning || chasing),
            "location": if returning || chasing { None } else { Some(PIRATE_BASE) },
            "position": position("raider-1", raider_point), "cargo": {"ore": war.raider_cargo},
            "fuel": war.raider_fuel, "fuel_capacity": 6,
            "transit": (returning || chasing).then(|| json!({
                "from": if returning { BELT } else { PIRATE_BASE },
                "to": if returning { PIRATE_BASE } else { EARTH },
            })),
        }));
    }
    if war.patrol == Patrol::Ready {
        let progress = war.patrol_progress();
        let sweeping = progress > 0.0;
        let mut center = crossing;
        center.y += 0.15;
        let point = if progress < 0.31 {
            interpolate(scene.station, center, progress / 0.31)
        } else if progress <= 0.74 {
            let angle = TAU * (progress - 0.31) / (0.74 - 0.31);
            Point {
                x: center.x + 0.18 * angle.sin(),
                y: center.y + 0.18 * (1.0 - angle.cos()),
            }
        } else {
            interpolate(center, scene.station, (progress - 0.74) / 0.26)
        };
        ships.push(json!({
            "id": "patrol-1", "name": "Патруль-001", "class": "patrol", "faction_id": FACTION,
            "docked": !sweeping, "location": (!sweeping).then_some(EARTH),
            "position": position("patrol-1", point), "cargo": {}, "fuel": war.patrol_fuel, "fuel_capacity": PATROL_SEED_FUEL,
            "status_label": if war.near_intercept() { "Патрулирует сектор" }
                else if sweeping && progress < 0.31 { "Летит в сектор" }
                else if sweeping { "Возвращается на базу" }
                else if war.patrol_cooldown > 0.0 { "На обслуживании" }
                else if war.patrol_fuel < 2 { "Ждёт топлива" }
                else { "Ждёт ремонта" },
            "transit": sweeping.then(|| json!({"from": EARTH, "to": "Патрульный сектор"})),
        }));
    }
    ships
}

fn facilities(sim: &Sim, scene: &Scene) -> Vec<Value> {
    let mut facilities = vec![
        json!({"id": EARTH, "name": "Станция Земли", "type": "station", "location": EARTH, "body_id": "earth",
               "x": scene.station.x, "y": scene.station.y, "faction_id": FACTION, "reserves": {"fuel": sim.station_fuel}}),
        json!({"id": BELT, "name": "Добывающая установка", "type": "mining_rig", "location": BELT, "body_id": "belt",
               "x": scene.rig.x, "y": scene.rig.y, "faction_id": FACTION, "reserves": {"fuel": sim.belt_fuel},
               "deposit": sim.deposit}),
    ];
    let phase = sim.construction.phase;
    let ready = sim.construction.yard_ready();
    facilities.push(json!({
        "id": SITE, "name": if ready { "Орбитальная верфь" } else { "Площадка верфи" },
        "type": if ready { "shipyard" } else { "construction_site" }, "location": SITE, "body_id": "earth",
        "x": scene.yard.x, "y": scene.yard.y, "faction_id": FACTION, "reserves": {"fuel": 0},
        "project": match phase {
            Project::WaitingMaterials => "Ждёт 24 металла на станции",
            Project::Hauling => "Строитель везёт материалы",
            Project::Assembling => "Идёт монтаж верфи",
            Project::Returning | Project::WaitingShip => "Верфь готова, ожидается запуск сборки",
            Project::BuildingShip => "Идёт сборка грузовика",
            Project::TransferringShip => "Грузовик вылетел к установке",
            Project::Complete => "Грузовик принят во флот",
        },
        "progress": match phase {
            Project::Assembling | Project::BuildingShip => Some(sim.construction.elapsed / sim.construction.duration()),
            _ => None,
        },
    }));
    let war = &sim.conflict;
    facilities.push(json!({
        "id": PIRATE_BASE, "name": if war.base_ready { "Пиратская база" } else { "Площадка пиратов" },
        "type": if war.base_ready { "pirate-station" } else { "construction_site" },
        "location": PIRATE_BASE, "body_id": "jupiter", "x": scene.pirate.x, "y": scene.pirate.y,
        "faction_id": "pirates", "reserves": {"fuel": war.pirate_fuel_stock},
        "project": if war.base_ready { format!("Трофеи: {} руды, {} металла", war.pirate_loot, war.pirate_metal) } else { "Экспедиция собирает базу".into() },
        "progress": (!war.base_ready).then_some(war.base_progress / 36.0),
    }));
    facilities
}

fn markets(sim: &Sim) -> Value {
    json!([
        {"id": BELT, "facility_location": BELT, "supply": {"ore": sim.belt_ore}},
        {"id": EARTH, "facility_location": EARTH,
         "supply": {"ore": sim.station_ore, "metals": sim.metal},
         "metal_capacity": METAL_CAPACITY,
         "delivery_status": sim.delivery_status(), "smelting_status": sim.smelting_status()},
    ])
}

fn governance(sim: &Sim) -> Value {
    let gov = &sim.governance;
    json!({
        "leader": gov.leader.label(),
        "policy": gov.policy.label(),
        "last_decision": gov.last_decision,
        "ore_target": gov.policy.ore_target(),
        "fuel_floor": gov.fuel_floor(),
        "logistics": sim.delivery_status(),
        "industry": sim.smelting_status(),
        "batch_active": sim.batch_active(),
        "station_ore": sim.station_ore,
        "station_fuel": sim.station_fuel,
        "metal": sim.metal,
        "cargo": sim.cargo,
        "ship": sim.ship_status(),
        "lost_ore": sim.conflict.lost_ore,
        "intercepted_raids": sim.conflict.intercepted_raids,
        "patrol_alert": if sim.conflict.heightened_alert() { "Повышенная готовность" } else { "Штатное патрулирование" },
        "fuel_cargo": sim.fuel_cargo,
    })
}

fn position(id: &str, point: Point) -> Value {
    json!({"id": id, "x": point.x, "y": point.y})
}

pub fn report(sim: &Sim, running: bool, speed: f64) -> Value {
    let scene = Scene::at(sim);
    json!({
        "tick": sim.tick, "running": running, "world_speed": speed, "genesis_ore_loop": true, "governance": governance(sim),
        "systems": [{"id": "sol", "name": "Sol", "offset_x": 0, "offset_y": 0, "bodies": [
            {"id": "earth", "name": "Земля", "type": "planet", "orbit_radius": 1.0,
             "x": scene.earth.x, "y": scene.earth.y, "controlling_faction": FACTION},
            {"id": "belt", "name": "Пояс астероидов", "type": "belt", "orbit_radius": 2.7,
             "x": scene.belt.x, "y": scene.belt.y, "controlling_faction": FACTION},
            {"id":"venus","name":"Венера","type":"planet","biome":"molten","orbit_radius":0.72,
             "x":scene.venus.x,"y":scene.venus.y},
            {"id":"mars","name":"Марс","type":"planet","biome":"desert","orbit_radius":1.52,
             "x":scene.mars.x,"y":scene.mars.y},
            {"id":"jupiter","name":"Юпитер","type":"planet","biome":"gas_giant","orbit_radius":5.20,
             "x":scene.jupiter.x,"y":scene.jupiter.y,"controlling_faction":"pirates"},
        ]}],
        "facilities": facilities(sim, &scene),
        "ships": ships(sim, &scene), "markets": markets(sim),
        "factions": [{"id": FACTION, "name": "Genesis", "colors": {"primary": "#6fb6d9"}}, {"id":"pirates", "name":"Пираты", "colors":{"primary":"#e06a58"}}],
    })
}

pub fn update(sim: &Sim, events: &[Event]) -> Value {
    let scene = Scene::at(sim);
    json!({
        "type": "genesis_update", "tick": sim.tick, "events": events, "governance": governance(sim),
        "entities": [
            position("earth", scene.earth), position("belt", scene.belt),
            position("venus", scene.venus), position("mars", scene.mars), position("jupiter", scene.jupiter),
            position(EARTH, scene.station), position(BELT, scene.rig), position(SITE, scene.yard),
        ],
        "ships": ships(sim, &scene), "markets": markets(sim), "facilities": facilities(sim, &scene),
    })
}
