use crate::conflict::{PATROL_METAL, PATROL_SEED_FUEL, PIRATE_BASE, Patrol};
use crate::freight::{Freighter, FreightPhase};
use crate::construction::{
    MARS_METAL, MARS_ORE, MARS_SITE, MarsProject, Project, SHIP_METAL, SITE, YARD_METAL,
};
use crate::planning::{Choice, Kind, Program, Site as BuildSite, Work};
use crate::sim::{BELT, EARTH, Event, Phase, SHIPMENT, Sim, TANK};
use serde_json::{Value, json};
use std::f64::consts::TAU;

const VENUS_ORBIT: f64 = 1.15;
const EARTH_ORBIT: f64 = 2.1;
const MARS_ORBIT: f64 = 3.5;
const BELT_ORBIT: f64 = 5.4;
const JUPITER_ORBIT: f64 = 9.0;

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
    mars_site: Point,
    jupiter: Point,
}

impl Scene {
    fn at(sim: &Sim) -> Self {
        let earth = orbit(EARTH_ORBIT, TAU * sim.seconds / 365.0);
        let belt = orbit(BELT_ORBIT, 2.1 + TAU * sim.seconds / 1680.0);
        let station = location(earth, 0.4 + TAU * sim.seconds / 90.0);
        let rig = location(belt, 2.0 + TAU * sim.seconds / 140.0);
        let offset = orbit(0.36, 2.8 + TAU * sim.seconds / 112.0);
        let mut yard = Point {
            x: earth.x + offset.x,
            y: earth.y + offset.y,
        };
        if sim.genesis_program.has(Kind::Yard)
            || sim
                .genesis_program
                .active
                .is_some_and(|work| work.choice.kind == Kind::Yard)
        {
            let point = location(earth, 2.1 + sim.seconds / 90.0);
            let offset = orbit(0.24, Kind::Yard as u32 as f64 * 1.3);
            yard = Point {
                x: point.x + offset.x,
                y: point.y + offset.y,
            };
        }
        let venus = orbit(VENUS_ORBIT, 1.2 + TAU * sim.seconds / 225.0);
        let mars = orbit(MARS_ORBIT, -0.8 + TAU * sim.seconds / 687.0);
        let jupiter = orbit(JUPITER_ORBIT, -2.3 + TAU * sim.seconds / 4333.0);
        let pirate = location(jupiter, 0.9 + TAU * sim.seconds / 180.0);
        let outpost = sim.outpost_site.or_else(|| {
            sim.genesis_program
                .active
                .filter(|work| work.choice.kind == Kind::Mine)
                .map(|work| work.choice.site)
        });
        let mars_site = if outpost == Some(BuildSite::Belt) {
            location(belt, 4.0 + TAU * sim.seconds / 162.0)
        } else {
            location(mars, 1.2 + TAU * sim.seconds / 121.0)
        };
        let source = if sim.mars_route { mars_site } else { rig };
        let progress = sim.elapsed / sim.freight_duration();
        let ship = match sim.phase {
            Phase::Relocating => interpolate(rig, mars_site, progress),
            Phase::Outbound => interpolate(source, station, progress),
            Phase::Loading => source,
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
            mars_site,
            jupiter,
        }
    }
}

fn build_point(scene: &Scene, site: BuildSite, seconds: f64) -> Point {
    match site {
        BuildSite::Earth => location(scene.earth, 2.1 + seconds / 90.0),
        BuildSite::Mars => location(scene.mars, 1.2 + TAU * seconds / 121.0),
        BuildSite::Belt => location(scene.belt, 4.0 + TAU * seconds / 162.0),
        BuildSite::Jupiter => location(scene.jupiter, 2.4 + seconds / 180.0),
        BuildSite::Outer => orbit(JUPITER_ORBIT + 1.4, -2.1 + seconds / 630.0),
        BuildSite::Solar => orbit(0.45, seconds / 60.0),
    }
}

fn chosen_point(scene: &Scene, choice: Choice, seconds: f64) -> Point {
    let point = build_point(scene, choice.site, seconds);
    if choice.kind == Kind::Mine {
        return point;
    }
    let offset = orbit(0.24, choice.kind as u32 as f64 * 1.3);
    Point {
        x: point.x + offset.x,
        y: point.y + offset.y,
    }
}

pub fn build_distance(sim: &Sim, pirates: bool, site: BuildSite) -> f64 {
    let scene = Scene::at(sim);
    let home = if pirates { scene.pirate } else { scene.station };
    let target = build_point(&scene, site, sim.seconds);
    (home.x - target.x).hypot(home.y - target.y)
}

fn build_id(pirates: bool, choice: Choice) -> String {
    if !pirates {
        match choice.kind {
            Kind::Mine => return MARS_SITE.into(),
            Kind::Yard => return SITE.into(),
            _ => {}
        }
    }
    format!(
        "{}-{}",
        if pirates { "pirate" } else { "genesis" },
        choice.kind.id()
    )
}

fn build_flight(sim: &Sim, scene: &Scene, pirates: bool, work: Work) -> Value {
    let (id, name, class, faction, home_id, home) = if pirates {
        (
            "pirate-builder-1",
            "Пиратский строитель",
            "pirate-builder",
            "pirates",
            PIRATE_BASE,
            scene.pirate,
        )
    } else {
        (
            "builder-1",
            "Строитель-001",
            "constructor",
            FACTION,
            EARTH,
            scene.station,
        )
    };
    let target_id = build_id(pirates, work.choice);
    let site = chosen_point(scene, work.choice, sim.seconds);
    let spec = work.choice.kind.spec();
    let returning = work.finished_assembly();
    let assembling = work.on_site() && !returning;
    let progress = if returning {
        1.0 - work.remaining / work.travel
    } else {
        2.0 + (spec.seconds - work.remaining) / work.travel
    };
    let point = if assembling {
        site
    } else if returning {
        interpolate(site, home, progress)
    } else {
        interpolate(home, site, progress)
    };
    json!({
        "id": id, "name": name, "class": class, "faction_id": faction, "docked": assembling,
        "location": assembling.then_some(&target_id), "position": position(id, point),
        "cargo": {"metals": if work.on_site() { 0 } else { spec.metal }},
        "fuel": if returning { 0 } else { work.fuel / 2 }, "fuel_capacity": work.fuel,
        "status_label": if assembling { "Монтирует сооружение" } else if returning { "Возвращается на базу" } else { "Везёт материалы" },
        "transit": (!assembling).then(|| json!({
            "from": if returning { &target_id } else { home_id },
            "to": if returning { home_id } else { &target_id },
            "distance_total": work.travel, "distance_travelled": progress * work.travel
        })),
    })
}

fn program_facilities(sim: &Sim, scene: &Scene, program: &Program, pirates: bool) -> Vec<Value> {
    let active = program.active;
    program.built.iter().map(|choice| (*choice, true, None))
        .chain(active.map(|work| (work.choice, false, Some(work))))
        .filter(|(choice, _, work)| pirates || !matches!(choice.kind, Kind::Mine | Kind::Yard) || work.is_some())
        .map(|(choice, ready, work)| {
            let id = build_id(pirates, choice);
            let p = chosen_point(scene, choice, sim.seconds);
            let spec = choice.kind.spec();
            let body = match choice.site {
                BuildSite::Earth => Some("earth"), BuildSite::Mars => Some("mars"),
                BuildSite::Belt => Some("belt"), BuildSite::Jupiter => Some("jupiter"),
                _ => None,
            };
            json!({"id": id, "name": if ready {spec.name.to_string()} else {format!("Площадка · {}",spec.name)},
                "type": if ready {choice.kind.id()} else {"construction_site"},
                "location":id, "body_id":body, "system_id":"sol", "x":p.x,"y":p.y,
                "faction_id":if pirates {"pirates"} else {FACTION}, "reserves":{"fuel":0},
                "project":work.map(|_| format!("{} · {} металла", choice.site.label(),spec.metal)),
                "progress":work.map(|w| ((w.travel+spec.seconds-w.remaining)/spec.seconds).clamp(0.0,1.0)),
            })
        }).collect()
}

pub fn route_distance(sim: &Sim, from: &str, to: &str) -> f64 {
    let scene = Scene::at(sim);
    let position = |id| match id {
        BELT => scene.rig,
        MARS_SITE => scene.mars_site,
        SITE => scene.yard,
        PIRATE_BASE => scene.pirate,
        _ => scene.station,
    };
    let a = position(from);
    let b = position(to);
    (a.x - b.x).hypot(a.y - b.y)
}

fn ship(sim: &Sim, scene: &Scene) -> Value {
    let source = if sim.mars_route { MARS_SITE } else { BELT };
    let (location, transit) = match sim.phase {
        Phase::Relocating => (None, Some((BELT, MARS_SITE))),
        Phase::Outbound => (None, Some((source, EARTH))),
        Phase::Loading => (Some(source), None),
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
            "from": from, "to": to, "distance_travelled": sim.elapsed, "distance_total": sim.freight_duration(),
        }))
    })
}

fn freighter_id(second: bool) -> &'static str {
    if second { "freighter-2" } else { "freighter-1" }
}

fn second_ship(ship: &Freighter, scene: &Scene) -> Value {
    let fraction = (ship.elapsed / ship.duration()).clamp(0.0, 1.0);
    let (location, transit, point) = match ship.phase {
        FreightPhase::Outbound => (
            None, Some((BELT, EARTH)), interpolate(scene.rig, scene.station, fraction)
        ),
        FreightPhase::Returning => (
            None, Some((EARTH, BELT)), interpolate(scene.station, scene.rig, fraction)
        ),
        FreightPhase::Unloading | FreightPhase::NoFuelAtEarth =>
            (Some(EARTH), None, scene.station),
        _ => (Some(BELT), None, scene.rig),
    };
    json!({
        "id":"freighter-2", "name":"Грузовой-002", "class":"freighter", "faction_id":FACTION,
        "docked":transit.is_none(), "location":location,
        "position":position("freighter-2",point),
        "fuel":ship.fuel, "fuel_capacity":TANK,
        "cargo":{"ore":ship.cargo, "fuel":ship.fuel_cargo},
        "status_label":ship.status(),
        "transit": transit.map(|(from,to)| json!({
            "from":from, "to":to, "distance_travelled":ship.elapsed,
            "distance_total":ship.duration()
        }))
    })
}

fn ships(sim: &Sim, scene: &Scene) -> Vec<Value> {
    let mut ships = vec![ship(sim, scene)];
    let phase = sim.construction.phase;
    let progress = sim.construction.elapsed / sim.construction.duration();
    let delivering_patrol = sim.conflict.patrol == Patrol::Delivering;
    let mars = sim.construction.mars;
    let mars_flight = matches!(
        mars,
        MarsProject::Positioning | MarsProject::Hauling | MarsProject::Returning
    );
    let (builder_elapsed, builder_duration) = if mars_flight {
        (
            sim.construction.mars_elapsed,
            sim.construction.mars_duration,
        )
    } else if delivering_patrol {
        (sim.conflict.patrol_elapsed, 4.0)
    } else {
        (sim.construction.elapsed, sim.construction.duration())
    };
    let builder_route = match phase {
        _ if mars == MarsProject::Positioning => Some((SITE, EARTH, scene.yard, scene.station)),
        _ if mars == MarsProject::Hauling => {
            Some((EARTH, MARS_SITE, scene.station, scene.mars_site))
        }
        _ if mars == MarsProject::Returning => {
            Some((MARS_SITE, EARTH, scene.mars_site, scene.station))
        }
        _ if delivering_patrol => Some((EARTH, SITE, scene.station, scene.yard)),
        Project::Hauling => Some((EARTH, SITE, scene.station, scene.yard)),
        Project::Returning => Some((SITE, EARTH, scene.yard, scene.station)),
        _ => None,
    };
    let dock = if mars == MarsProject::Building {
        (MARS_SITE, scene.mars_site)
    } else if phase == Project::Assembling
        || matches!(sim.conflict.patrol, Patrol::Building | Patrol::Ready)
            && mars != MarsProject::Ready
    {
        (SITE, scene.yard)
    } else {
        (EARTH, scene.station)
    };
    let builder = builder_route.map_or(dock.1, |(_, _, from, to)| {
        interpolate(from, to, builder_elapsed / builder_duration)
    });
    ships.push(json!({
        "id": "builder-1", "name": "Строитель-001", "class": "constructor",
        "faction_id": FACTION, "docked": builder_route.is_none(),
        "location": if builder_route.is_some() { None } else { Some(dock.0) },
        "fuel": sim.construction.builder_fuel() + if sim.conflict.patrol == Patrol::None { 4 } else { 0 }, "fuel_capacity": 12,
        "position": position("builder-1", builder),
        "cargo": {
            "metals": if mars == MarsProject::Hauling { MARS_METAL } else if delivering_patrol { PATROL_METAL } else if phase == Project::Hauling { YARD_METAL + SHIP_METAL } else { 0 },
            "fuel": if delivering_patrol { PATROL_SEED_FUEL } else if phase == Project::Hauling { 8 } else { 0 }
        },
        "status_label": if mars == MarsProject::Positioning { "Летит за материалами" } else if mars == MarsProject::Hauling { "Везёт материалы на Марс" } else if mars == MarsProject::Building { "Собирает аванпост" } else if mars == MarsProject::Returning { "Возвращается с Марса" } else if delivering_patrol { "Везёт материалы для патруля" } else { match phase {
            Project::WaitingMaterials => "Ждёт металл",
            Project::Hauling => "Везёт стройматериалы",
            Project::Assembling => "Собирает верфь",
            Project::Returning => "Возвращается на станцию",
            _ => "У причала",
        } },
        "transit": builder_route.map(|(from, to, _, _)| json!({
            "from": from, "to": to, "distance_travelled": builder_elapsed,
            "distance_total": builder_duration,
        })),
    }));
    if let Some(freighter) = sim.second_freighter.as_ref() {
        ships.push(second_ship(freighter,scene));
    } else if matches!(phase, Project::TransferringShip | Project::Complete) {
        // Legacy save in the middle of its old rotating-freighter model;
        // preserve the old representation until safely migrated on return.
        let transferring = phase == Project::TransferringShip;
        let id = freighter_id(!sim.construction.active_second);
        let point = if transferring {
            interpolate(scene.yard,scene.rig,progress)
        } else { scene.rig };
        ships.push(json!({
            "id":id, "name":if sim.construction.active_second { "Грузовой-001" } else { "Грузовой-002" },
            "class":"freighter", "faction_id":FACTION,
            "docked":!transferring, "location":if transferring {None} else {Some(BELT)},
            "fuel":sim.construction.parked_fuel, "fuel_capacity":TANK,
            "cargo":{"ore":0},
            "position":position(id,point),
            "transit":transferring.then(||json!({
                "from":SITE, "to":BELT,
                "distance_travelled":sim.construction.elapsed,
                "distance_total":sim.construction.duration()
            }))
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
            war.raider_return / war.return_duration(),
        )
    } else if chasing {
        interpolate(
            scene.pirate,
            crossing,
            war.raid_elapsed / war.approach_duration(),
        )
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
    if war.base_progress >= 40.0 && !war.raider_destroyed {
        let id = format!("raider-{}", war.raider_generation + 1);
        ships.push(json!({
            "id": id, "name": "Пиратский рейдер", "class": "pirate-patrol",
            "faction_id": "pirates", "docked": !(returning || chasing),
            "location": if returning || chasing { None } else { Some(PIRATE_BASE) },
            "position": position(&id, raider_point), "cargo": {"ore": war.raider_cargo},
            "fuel": war.raider_fuel, "fuel_capacity": 6, "hull": 60u32.saturating_sub(war.raider_damage), "max_hull": 60,
            "transit": (returning || chasing).then(|| json!({
                "from": if returning { BELT } else { PIRATE_BASE },
                "to": if returning { PIRATE_BASE } else { EARTH },
            })),
        }));
    }
    if war.patrol == Patrol::Ready {
        let id = format!("patrol-{}", war.patrol_generation + 1);
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
            "id": id, "name": "Патруль-001", "class": "patrol", "faction_id": FACTION,
            "docked": !sweeping, "location": (!sweeping).then_some(EARTH),
            "position": position(&id, point), "cargo": {}, "fuel": war.patrol_fuel, "fuel_capacity": PATROL_SEED_FUEL,
            "hull": 100u32.saturating_sub(war.patrol_damage), "max_hull": 100,
            "status_label": if war.near_intercept() { "Патрулирует сектор" }
                else if sweeping && progress < 0.31 { "Летит в сектор" }
                else if sweeping { "Возвращается на базу" }
                else if war.patrol_cooldown > 0.0 { "На обслуживании" }
                else if war.patrol_fuel < 2 { "Ждёт топлива" }
                else { "Ждёт ремонта" },
            "transit": sweeping.then(|| json!({"from": EARTH, "to": "Патрульный сектор"})),
        }));
    }
    for (pirates, program, id) in [
        (false, &sim.genesis_program, "builder-1"),
        (true, &sim.pirate_program, "pirate-builder-1"),
    ] {
        if let Some(work) = program.active {
            if let Some(entry) = ships.iter_mut().find(|ship| ship["id"] == id) {
                *entry = build_flight(sim, scene, pirates, work);
            }
        }
    }
    ships
}

fn gauge(label: &str, value: f64, capacity: f64, unit: &str) -> Value {
    json!({"label":label, "value":value, "capacity":capacity, "unit":unit})
}

fn stock(label: &str, amount: u32) -> Value {
    json!({"label":label, "value":amount})
}

fn facility_inspection(sim: &Sim, facility: &Value) -> Value {
    let id = facility["id"].as_str().unwrap_or_default();
    let kind = facility["type"].as_str().unwrap_or_default();
    let pirates = facility["faction_id"] == "pirates";
    let war = &sim.conflict;
    let program = if pirates {
        &sim.pirate_program
    } else {
        &sim.genesis_program
    };
    let mut resources = Vec::new();
    let mut meters = Vec::new();
    let mut note = String::new();
    if let Some(work) = program
        .active
        .filter(|work| build_id(pirates, work.choice) == id)
    {
        let spec = work.choice.kind.spec();
        let progress =
            ((work.travel + spec.seconds - work.remaining) / spec.seconds).clamp(0.0, 1.0);
        let status = if work.finished_assembly() {
            "Строитель возвращается · ждёт ввода в строй"
        } else if work.on_site() {
            "Идёт монтаж"
        } else {
            "Материалы в пути"
        };
        return json!({
            "status":status,
            "note":format!("{} · {}. Топливо выделено на рейс строителя: {}.", spec.name, work.choice.site.label(), work.fuel),
            "resources":[stock(if work.on_site() {"Металл доставлен"} else {"Металл в трюме строителя"}, spec.metal)],
            "meters":[gauge("Монтаж", progress * 100.0, 100.0, "%")],
        });
    }
    let status = match (id, kind) {
        (EARTH, _) | (_, "smelter") if !pirates => {
            let (elapsed, duration) = sim.smelting_cycle();
            meters.push(gauge(
                "Металл на складе станции",
                sim.metal as f64,
                sim.metal_capacity() as f64,
                "ед.",
            ));
            if sim.batch_active() {
                meters.push(gauge("Плавка партии", elapsed, duration, "с"));
            }
            resources.extend([
                stock("Руда на станции", sim.station_ore),
                stock("Топливо на станции", sim.station_fuel),
            ]);
            note = format!(
                "Партия: 10 руды + 1 топливо → 8 металла. Снабжение: {}.",
                sim.delivery_status()
            );
            if sim.metal_capacity() - sim.metal < 8 && !sim.batch_active() {
                note.push_str(&format!(
                    " Свободно {} мест, для партии нужно 8.",
                    sim.metal_capacity() - sim.metal
                ));
            }
            sim.smelting_status()
        }
        (_, "mining_rig") => {
            let original = id == BELT;
            let ore = if original {
                sim.belt_ore
            } else {
                sim.construction.mars_ore
            };
            let deposit = if original {
                sim.deposit
            } else {
                MARS_ORE - sim.construction.mars_extracted
            };
            let (cycle, status) = sim.mining_cycle(id);
            resources.push(stock("Руда на складе", ore));
            if original {
                resources.push(stock("Топливо на складе", sim.belt_fuel));
            }
            meters.push(gauge(
                "Руда к погрузке",
                ore.min(SHIPMENT) as f64,
                SHIPMENT as f64,
                "ед.",
            ));
            meters.push(gauge(
                "Остаток залежи",
                deposit as f64,
                if original { 500.0 } else { MARS_ORE as f64 },
                "ед.",
            ));
            if status == "Добывает руду" {
                meters.push(gauge("Добыча партии", cycle * 100.0, 100.0, "%"));
            }
            status
        }
        (_, "cargo_warehouse") if !pirates => {
            meters.push(gauge(
                "Металл в общей ёмкости",
                sim.metal as f64,
                sim.metal_capacity() as f64,
                "ед.",
            ));
            note = "Расширяет общий склад металла станции Земли.".into();
            "Склад подключён"
        }
        (PIRATE_BASE, "pirate-station") | (_, "cargo_warehouse") | (_, "smelter") if pirates => {
            let cap = if program.has(Kind::Warehouse) { 60 } else { 20 };
            meters.push(gauge(
                "Трофейная руда на базе",
                war.pirate_loot as f64,
                cap as f64,
                "ед.",
            ));
            resources.extend([
                stock("Металл на базе", war.pirate_metal),
                stock("Топливо на базе", war.pirate_fuel_stock),
            ]);
            note = if kind == "smelter" {
                "Перерабатывает трофейную руду в металл для ремонта и стройки.".into()
            } else {
                "Запасы используются для снабжения рейдера и строительства.".into()
            };
            if kind == "smelter" && war.pirate_loot < 10 {
                "Ждёт партию трофейной руды"
            } else if kind == "smelter" && war.pirate_fuel_stock == 0 {
                "Ждёт топливо"
            } else if kind == "smelter" && war.raider_return > 0.0 {
                "Ждёт возвращения рейдера"
            } else if kind == "smelter" {
                "Партия доступна"
            } else if war.raider_destroyed {
                "Рейдер потерян"
            } else if war.raid_elapsed > 0.0 {
                "Рейдер на вылете"
            } else if war.raider_return > 0.0 {
                "Рейдер возвращается"
            } else {
                "База в работе"
            }
        }
        (_, "shipyard") if pirates => {
            resources.extend([
                stock("Металл на базе", war.pirate_metal),
                stock("Топливо на базе", war.pirate_fuel_stock),
            ]);
            note = "Новый рейдер требует 8 металла и 2 топлива со склада базы.".into();
            if war.rebuild_elapsed > 0.0 {
                meters.push(gauge("Новый рейдер", war.rebuild_elapsed, 16.0, "с"));
                "Собирает рейдер"
            } else if war.raider_destroyed {
                "Ждёт материалы для замены"
            } else {
                "Свободна"
            }
        }
        (SITE, "shipyard") => {
            resources.extend([
                stock("Металл на Земле", sim.metal),
                stock("Топливо на Земле", sim.station_fuel),
            ]);
            if sim.construction.phase == Project::BuildingShip {
                meters.push(gauge(
                    "Сборка грузовика",
                    sim.construction.elapsed,
                    sim.construction.duration(),
                    "с",
                ));
                "Собирает грузовик"
            } else if matches!(war.patrol, Patrol::Building | Patrol::Rebuilding) {
                meters.push(gauge(
                    "Сборка патруля",
                    war.patrol_elapsed,
                    if war.patrol == Patrol::Building {
                        8.0
                    } else {
                        16.0
                    },
                    "с",
                ));
                "Собирает патруль"
            } else {
                "Свободна"
            }
        }
        (_, "repair_dock") => {
            let (metal, damage, hull): (u32, u32, u32) = if pirates {
                (war.pirate_metal, war.raider_damage, 60)
            } else {
                (sim.metal, war.patrol_damage, 100)
            };
            resources.push(stock(
                if pirates {
                    "Металл на базе"
                } else {
                    "Металл на Земле"
                },
                metal,
            ));
            if (pirates && war.raider_destroyed) || (!pirates && war.patrol != Patrol::Ready) {
                "Ждёт корабль"
            } else {
                meters.push(gauge(
                    "Корпус корабля",
                    hull.saturating_sub(damage) as f64,
                    hull as f64,
                    "ед.",
                ));
                if damage == 0 {
                    "Ремонт не требуется"
                } else if metal < if pirates { 2 } else { 4 } {
                    "Ждёт металл"
                } else {
                    "Ремонт доступен на базе"
                }
            }
        }
        (_, "observation_station") => {
            resources.extend([
                stock("Перехваты", war.intercepted_raids),
                stock("Потери руды", war.lost_ore),
            ]);
            note = if pirates {
                "Помогает рейдеру позже попасть под обнаружение.".into()
            } else {
                "Даёт патрулю больше времени обнаружить рейдер в секторе.".into()
            };
            "Наблюдает за маршрутом"
        }
        (_, "construction_site") => {
            if let Some(progress) = facility["progress"].as_f64() {
                meters.push(gauge("Строительство", progress * 100.0, 100.0, "%"));
            }
            note = facility["project"].as_str().unwrap_or_default().into();
            if id == PIRATE_BASE {
                resources.extend([
                    stock("Металл у экспедиции", 16),
                    stock("Топливо экспедиции", war.pirate_fuel_stock),
                ]);
            }
            "Строительство"
        }
        _ => "В строю",
    };
    json!({"status":status, "note":note, "resources":resources, "meters":meters})
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
    if phase != Project::WaitingMaterials {
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
    }
    let mars = sim.construction.mars;
    if mars != MarsProject::Proposed {
        let ready = matches!(mars, MarsProject::Returning | MarsProject::Ready);
        facilities.push(json!({
            "id": MARS_SITE, "name": if ready { "Рудный аванпост" } else { "Площадка Марса" },
            "type": if ready { "mining_rig" } else { "construction_site" },
            "location": MARS_SITE, "body_id": if sim.outpost_site == Some(BuildSite::Belt) { "belt" } else { "mars" }, "x": scene.mars_site.x, "y": scene.mars_site.y,
            "faction_id": FACTION, "reserves": {"fuel": 0},
            "deposit": MARS_ORE - sim.construction.mars_extracted,
            "project": format!("Затраты {MARS_METAL} металла · Руда на складе: {}", sim.construction.mars_ore),
        }));
    }
    let war = &sim.conflict;
    facilities.push(json!({
        "id": PIRATE_BASE, "name": if war.base_ready { "Пиратская база" } else { "Площадка пиратов" },
        "type": if war.base_ready { "pirate-station" } else { "construction_site" },
        "location": PIRATE_BASE, "body_id": "jupiter", "x": scene.pirate.x, "y": scene.pirate.y,
        "faction_id": "pirates", "reserves": {"fuel": war.pirate_fuel_stock},
        "project": if war.base_ready { format!("Трофеи: {} руды, {} металла", war.pirate_loot, war.pirate_metal) } else { "Экспедиция собирает базу".into() },
        "progress": (!war.base_ready).then_some(war.base_progress / 36.0),
    }));
    facilities.extend(program_facilities(sim, scene, &sim.genesis_program, false));
    facilities.extend(program_facilities(sim, scene, &sim.pirate_program, true));
    for facility in &mut facilities {
        facility["inspection"] = facility_inspection(sim, facility);
    }
    facilities
}

fn markets(sim: &Sim) -> Value {
    json!([
        {"id": BELT, "facility_location": BELT, "supply": {"ore": sim.belt_ore}},
        {"id": EARTH, "facility_location": EARTH,
         "supply": {"ore": sim.station_ore, "metals": sim.metal},
         "metal_capacity": sim.metal_capacity(),
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
        "expansion": sim.mars_status(),
        "pirate_expansion": sim.pirate_program.decision,
        "catalog": crate::planning::CATALOG.iter().map(|spec| json!({
            "kind":spec.kind, "name":spec.name, "metal":spec.metal, "seconds":spec.seconds,
            "sites":spec.sites.iter().map(|site| site.label()).collect::<Vec<_>>(), "enabled":spec.enabled,
        })).collect::<Vec<_>>(),
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
            {"id": "earth", "name": "Земля", "type": "planet", "orbit_radius": EARTH_ORBIT,
             "x": scene.earth.x, "y": scene.earth.y, "controlling_faction": FACTION},
            {"id": "belt", "name": "Пояс астероидов", "type": "belt", "orbit_radius": BELT_ORBIT,
             "x": scene.belt.x, "y": scene.belt.y, "controlling_faction": FACTION},
            {"id":"venus","name":"Венера","type":"planet","biome":"molten","orbit_radius":VENUS_ORBIT,
             "x":scene.venus.x,"y":scene.venus.y},
            {"id":"mars","name":"Марс","type":"planet","biome":"desert","orbit_radius":MARS_ORBIT,
             "x":scene.mars.x,"y":scene.mars.y},
            {"id":"jupiter","name":"Юпитер","type":"planet","biome":"gas_giant","orbit_radius":JUPITER_ORBIT,
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
            position("venus", scene.venus), position("mars", scene.mars), position(MARS_SITE, scene.mars_site), position("jupiter", scene.jupiter),
            position(EARTH, scene.station), position(BELT, scene.rig), position(SITE, scene.yard),
        ],
        "ships": ships(sim, &scene), "markets": markets(sim), "facilities": facilities(sim, &scene),
    })
}
