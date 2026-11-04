use crate::builds::Stage;
use crate::conflict::{PATROL_METAL, PATROL_SEED_FUEL, PIRATE_BASE, Patrol};

use crate::construction::{
    MARS_METAL, MARS_SITE, MarsProject, Project, SHIP_METAL, SITE, YARD_METAL,
};
use crate::freight::{Commodity, ShipRole};
use crate::industry::Operation;
use crate::planning::{Choice, Kind, Program, Site as BuildSite};
use crate::sim::{BELT, EARTH, Event, Sim, TANK};
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
        Self {
            earth,
            belt,
            station,
            rig,
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

pub fn build_distance(sim: &Sim, origin: &str, site: BuildSite) -> f64 {
    let scene = Scene::at(sim);
    let home = local_point(sim, &scene, origin);
    let target = build_point(&scene, site, sim.seconds);
    (home.x - target.x).hypot(home.y - target.y)
}

pub(crate) fn build_id(pirates: bool, choice: Choice) -> String {
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

fn site_body(site: BuildSite) -> Option<&'static str> {
    match site {
        BuildSite::Earth => Some("earth"),
        BuildSite::Mars => Some("mars"),
        BuildSite::Belt => Some("belt"),
        BuildSite::Jupiter => Some("jupiter"),
        _ => None,
    }
}

fn project_point(scene: &Scene, id: &str, choice: Choice, seconds: f64) -> Point {
    let point = chosen_point(scene, choice, seconds);
    let Some(index) = id
        .strip_prefix("site-")
        .and_then(|value| value.parse::<u64>().ok())
    else {
        return point;
    };
    let offset = orbit(0.26, index as f64 * 2.39996);
    Point {
        x: point.x + offset.x,
        y: point.y + offset.y,
    }
}

fn program_facilities(sim: &Sim, scene: &Scene, program: &Program, pirates: bool) -> Vec<Value> {
    program.built.iter().copied()
        .filter(|choice| pirates || !matches!(choice.kind, Kind::Mine | Kind::Yard))
        .filter_map(|choice| {
            let id = build_id(pirates, choice);
            if sim.builds.projects.contains_key(&id) { return None; }
            let p = chosen_point(scene, choice, sim.seconds);
            Some(json!({"id": id, "name": choice.kind.spec().name,
                "type": choice.kind.id(), "location": id, "body_id":site_body(choice.site),
                "system_id":"sol", "x":p.x,"y":p.y,
                "faction_id":if pirates {"pirates"} else {FACTION}, "reserves":{"fuel":sim.stock(&id, Commodity::Fuel)},
            }))
        }).collect()
}

fn local_point(sim: &Sim, scene: &Scene, id: &str) -> Point {
    if let Some(job) = sim.builds.projects.get(id) {
        return project_point(scene, id, job.choice, sim.seconds);
    }
    if let Some(choice) = sim
        .pirate_program
        .built
        .iter()
        .find(|choice| build_id(true, **choice) == id)
    {
        return chosen_point(scene, *choice, sim.seconds);
    }
    match id {
        BELT => scene.rig,
        MARS_SITE => scene.mars_site,
        SITE => scene.yard,
        PIRATE_BASE => scene.pirate,
        EARTH => scene.station,
        _ => sim.warehouses.get(id).map_or(scene.station, |stock| Point {
            x: stock.x,
            y: stock.y,
        }),
    }
}

pub fn route_distance(sim: &Sim, from: &str, to: &str) -> f64 {
    let scene = Scene::at(sim);
    let a = local_point(sim, &scene, from);
    let b = local_point(sim, &scene, to);
    (a.x - b.x).hypot(a.y - b.y)
}

fn freight_ships(sim: &Sim, scene: &Scene) -> Vec<Value> {
    sim.fleet.ships.iter().filter(|(id, _)| !sim.legacy_builder_busy(id)).map(|(id, ship)| {
        let start = local_point(sim, scene, &ship.location);
        let class = match ship.role {
            ShipRole::Freighter => "freighter",
            ShipRole::Constructor if ship.owner.id() == "pirates" => "pirate-builder",
            ShipRole::Constructor => "constructor",
        };
        if let Some((target, job, trip)) = sim.builds.builder_job(id) {
            let site = local_point(sim, scene, target);
            let elapsed = trip.travel.saturating_sub(trip.left);
            let progress = f64::from(elapsed) / f64::from(trip.travel);
            let (point, transit) = match trip.stage {
                Stage::Outbound => (interpolate(start, site, progress), Some((&*ship.location, target))),
                Stage::Assembly => (site, None),
                Stage::Returning => (interpolate(site, start, progress), Some((target, &*ship.location))),
            };
            return json!({"id":id, "name":ship.name, "class":class, "faction_id":ship.owner.id(),
                "docked":transit.is_none(), "location":transit.is_none().then_some(target),
                "position":position(id,point), "fuel":ship.fuel + if trip.stage == Stage::Returning { 0 } else { trip.return_fuel },
                "fuel_capacity":ship.tank, "status_label":job.status(),
                "cargo":{"metals":if trip.stage == Stage::Outbound { job.choice.kind.spec().metal } else { 0 }},
                "transit":transit.map(|(from,to)| json!({"from":from,"to":to,"distance_travelled":elapsed,"distance_total":trip.travel}))
            });
        }
        let point = ship.leg.as_ref().map_or(start, |leg| interpolate(start, local_point(sim, scene, &leg.destination), leg.progress()));
        let mut cargo = serde_json::Map::new();
        if let Some(task) = ship.task.as_ref().filter(|task| task.loaded) {
            cargo.insert(sim.fleet.orders[&task.order].resource.as_str().into(), json!(task.quantity));
        }
        json!({
            "id":id, "name":ship.name, "class":class, "faction_id":ship.owner.id(),
            "docked":ship.leg.is_none(), "location":ship.leg.is_none().then_some(&ship.location),
            "position":position(id, point), "cargo":cargo, "fuel":ship.fuel, "fuel_capacity":ship.tank,
            "status_label":ship.status, "task_id":ship.task.as_ref().map(|task| &task.order),
            "transit":ship.leg.as_ref().map(|leg| json!({"from":ship.location, "to":leg.destination,
                "distance_travelled":leg.elapsed, "distance_total":leg.duration})),
        })
    }).collect()
}

fn ships(sim: &Sim, scene: &Scene) -> Vec<Value> {
    let mut ships = freight_ships(sim, scene);
    let phase = sim.construction.phase;
    let progress = sim.construction.elapsed / sim.construction.duration();
    if sim.legacy_builder_busy("builder-1") {
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
    }
    if phase == Project::TransferringShip {
        ships.push(json!({
            "id":"freighter-2", "name":"Грузовой-002", "class":"freighter", "faction_id":FACTION,
            "docked":false, "position":position("freighter-2", interpolate(scene.yard,scene.rig,progress)),
            "fuel":sim.construction.parked_fuel, "fuel_capacity":TANK, "cargo":{},
            "transit":{"from":SITE, "to":BELT, "distance_travelled":sim.construction.elapsed,
                "distance_total":sim.construction.duration()}
        }));
    }
    let war = &sim.conflict;
    let crossing = interpolate(
        local_point(sim, scene, war.raid_source.as_deref().unwrap_or(BELT)),
        scene.station,
        0.5,
    );
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
    ships
}

fn gauge(label: &str, value: f64, capacity: f64, unit: &str) -> Value {
    json!({"label":label, "value":value, "capacity":capacity, "unit":unit})
}

fn stock(label: &str, amount: u32) -> Value {
    json!({"label":label, "value":amount})
}

fn resource_label(resource: Commodity) -> &'static str {
    match resource {
        Commodity::Ore => "Руда",
        Commodity::Fuel => "Топливо",
        Commodity::Metals => "Металл",
        Commodity::Ice => "Лёд",
        Commodity::Gas => "Газ",
        Commodity::Polymers => "Полимеры",
        Commodity::Water => "Вода",
        Commodity::Components => "Компоненты",
        Commodity::Electronics => "Электроника",
        Commodity::Tools => "Инструменты",
        Commodity::Food => "Продовольствие",
        Commodity::Medical => "Медикаменты",
        Commodity::Luxury => "Предметы роскоши",
    }
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
    if let Some(job) = sim.builds.projects.get(id).filter(|job| !job.done) {
        let spec = job.choice.kind.spec();
        let progress = job.journey.as_ref().map_or(0.0, |trip| match trip.stage {
            Stage::Outbound => 0.0,
            Stage::Assembly => (spec.seconds - f64::from(trip.left) / 4.0).max(0.0),
            Stage::Returning => spec.seconds,
        });
        let builder = job
            .journey
            .as_ref()
            .and_then(|trip| sim.fleet.ships.get(&trip.builder));
        return json!({"status":job.status(), "note":format!("{} · {}. {}", spec.name, job.choice.site.label(),
            builder.map_or("Исполнитель ещё не назначен.", |ship| ship.name.as_str())),
            "resources":[stock("Металл на проект", spec.metal)],
            "meters":[gauge("Монтаж",progress,spec.seconds,"с")]});
    }
    if let Some(yard) = sim.builds.yards.get(id).filter(|_| {
        id != SITE
            || !matches!(
                sim.construction.phase,
                Project::WaitingShip | Project::BuildingShip | Project::TransferringShip
            )
    }) {
        let (status, note, meters) = yard.order.as_ref().map_or(
            ("Верфь готова", String::new(), Vec::new()),
            |order| {
                let (status, meters) = order.remaining.map_or(
                    ("Ждёт материалы и топливо", Vec::new()),
                    |left| {
                        (
                            "Собирает корпус",
                            vec![gauge("Сборка", 8.0 - f64::from(left) / 4.0, 8.0, "с")],
                        )
                    },
                );
                (status, order.role.label().to_string(), meters)
            },
        );
        return json!({"status":status, "note":note, "meters":meters,
            "resources":[stock("Металл на верфи",sim.stock(id,Commodity::Metals)),stock("Топливо на верфи",sim.stock(id,Commodity::Fuel))]});
    }
    let stock_id = if kind == "smelter" && !pirates && !sim.warehouses.contains_key(id) {
        EARTH
    } else {
        id
    };
    if let Some(warehouse) = sim.warehouses.get(stock_id) {
        let plants: Vec<_> = sim
            .industry
            .plants
            .values()
            .filter(|plant| plant.location == stock_id)
            .collect();
        let mut meters = Vec::new();
        let mut notes = Vec::new();
        if warehouse.limits.is_empty() {
            meters.push(gauge(
                "Заполнение склада",
                warehouse.used() as f64,
                warehouse.capacity as f64,
                "ед.",
            ));
        } else {
            for &resource in Commodity::ALL {
                if let Some(&capacity) = warehouse.limits.get(&resource) {
                    meters.push(gauge(
                        resource_label(resource),
                        warehouse.quantity(resource) as f64,
                        capacity as f64,
                        "ед.",
                    ));
                }
            }
        }
        for plant in &plants {
            if let Some(batch) = &plant.batch {
                meters.push(gauge(
                    "Партия",
                    (batch.duration - batch.remaining) as f64 / 4.0,
                    batch.duration as f64 / 4.0,
                    "с",
                ));
            }
            if let Operation::Extract { deposit, .. } = &plant.operation {
                let source = &sim.industry.deposits[deposit];
                meters.push(gauge(
                    "Остаток залежи",
                    source.remaining as f64,
                    source.initial as f64,
                    "ед.",
                ));
            }
            if let Some(recipe) = plant.recipe() {
                let format = |items: &[(Commodity, u32)]| {
                    items
                        .iter()
                        .map(|&(resource, amount)| {
                            format!("{amount} × {}", resource_label(resource))
                        })
                        .collect::<Vec<_>>()
                        .join(" + ")
                };
                notes.push(format!(
                    "{} → {}. {}",
                    format(recipe.inputs),
                    format(recipe.outputs),
                    plant.status(sim)
                ));
            }
        }
        if stock_id != id {
            notes.push("Использует склад станции Земли.".into());
        }
        let status = plants.first().map_or(
            if warehouse.used() == warehouse.capacity && warehouse.limits.is_empty() {
                "Склад заполнен"
            } else {
                "Готов принимать груз"
            },
            |plant| plant.status(sim),
        );
        return json!({"status":status, "note":notes.join(" "),
            "resources":Commodity::ALL.iter().filter(|item| warehouse.stock.contains_key(item))
                .map(|&item| stock(resource_label(item), warehouse.quantity(item))).collect::<Vec<_>>(),
            "meters":meters});
    }
    let mut resources = Vec::new();
    let mut meters = Vec::new();
    let mut note = String::new();
    let status = match (id, kind) {
        (_, "cargo_warehouse") if !pirates => {
            meters.push(gauge(
                "Металл в общей ёмкости",
                sim.metal() as f64,
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
                stock("Металл на Земле", sim.metal()),
                stock("Топливо на Земле", sim.station_fuel()),
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
                (sim.metal(), war.patrol_damage, 100)
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
               "x": scene.station.x, "y": scene.station.y, "faction_id": FACTION, "reserves": {"fuel": sim.station_fuel()}}),
        json!({"id": BELT, "name": "Добывающая установка", "type": "mining_rig", "location": BELT, "body_id": "belt",
               "x": scene.rig.x, "y": scene.rig.y, "faction_id": FACTION, "reserves": {"fuel": sim.belt_fuel()},
               "deposit": sim.deposit()}),
    ];
    let phase = sim.construction.phase;
    let ready = sim.construction.yard_ready();
    if phase != Project::WaitingMaterials && !sim.builds.projects.contains_key(SITE) {
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
    if mars != MarsProject::Proposed && !sim.builds.projects.contains_key(MARS_SITE) {
        let ready = matches!(mars, MarsProject::Returning | MarsProject::Ready);
        facilities.push(json!({
            "id": MARS_SITE, "name": if ready { "Рудный аванпост" } else { "Площадка Марса" },
            "type": if ready { "mining_rig" } else { "construction_site" },
            "location": MARS_SITE, "body_id": if sim.outpost_site == Some(BuildSite::Belt) { "belt" } else { "mars" }, "x": scene.mars_site.x, "y": scene.mars_site.y,
            "faction_id": FACTION, "reserves": {"fuel": 0},
            "deposit": sim.deposit_remaining(MARS_SITE),
            "project": format!("Затраты {MARS_METAL} металла · Руда на складе: {}", sim.stock(MARS_SITE, Commodity::Ore)),
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
    for (id, job) in &sim.builds.projects {
        let point = local_point(sim, scene, id);
        let name = job.choice.kind.spec().name;
        facilities.push(json!({"id":id, "name":if job.done {name.into()} else {format!("Площадка · {name}")},
            "type":if job.done {job.choice.kind.id()} else {"construction_site"},
            "location":id, "body_id":site_body(job.choice.site), "system_id":"sol", "x":point.x,"y":point.y,
            "faction_id":job.owner.id(), "reserves":{"fuel":sim.stock(id,Commodity::Fuel)}}));
    }
    for (id, warehouse) in &sim.warehouses {
        if matches!(id.as_str(), EARTH | BELT | MARS_SITE | SITE)
            || sim.builds.projects.contains_key(id)
            || sim
                .pirate_program
                .built
                .iter()
                .any(|choice| build_id(true, *choice) == *id)
        {
            continue;
        }
        let kind = if sim.builds.yards.contains_key(id) {
            "shipyard"
        } else {
            sim.industry
                .plants
                .values()
                .find(|plant| &plant.location == id)
                .map_or("cargo_warehouse", |plant| match plant.operation {
                    Operation::Extract { .. } => "mining_rig",
                    Operation::Process { .. } => "smelter",
                })
        };
        facilities.push(json!({"id":id, "name":warehouse.name, "location":id, "type":kind,
            "system_id":"sol", "x":warehouse.x, "y":warehouse.y, "faction_id":warehouse.owner.id(),
            "reserves":{"fuel":warehouse.stock.get(&crate::freight::Commodity::Fuel).copied().unwrap_or(0)},
            "stock":warehouse.stock, "capacity":warehouse.capacity}));
    }
    for facility in &mut facilities {
        facility["inspection"] = facility_inspection(sim, facility);
    }
    facilities
}

fn markets(sim: &Sim) -> Value {
    json!([
        {"id": BELT, "facility_location": BELT, "supply": {"ore": sim.belt_ore()}},
        {"id": EARTH, "facility_location": EARTH,
         "supply": {"ore": sim.station_ore(), "metals": sim.metal()},
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
        "station_ore": sim.station_ore(),
        "station_fuel": sim.station_fuel(),
        "metal": sim.metal(),
        "cargo": sim.fleet.ships.values().filter_map(|ship| ship.task.as_ref()).filter(|task| task.loaded && sim.fleet.orders[&task.order].resource == crate::freight::Commodity::Ore).map(|task| task.quantity).sum::<u32>(),
        "ship": sim.delivery_status(),
        "lost_ore": sim.conflict.lost_ore,
        "intercepted_raids": sim.conflict.intercepted_raids,
        "patrol_alert": if sim.conflict.heightened_alert() { "Повышенная готовность" } else { "Штатное патрулирование" },
        "fuel_cargo": sim.fleet.ships.values().filter_map(|ship| ship.task.as_ref()).filter(|task| task.loaded && sim.fleet.orders[&task.order].resource == crate::freight::Commodity::Fuel).map(|task| task.quantity).sum::<u32>(),
        "orders": sim.fleet.orders.iter().map(|(id, order)| json!({
            "id":id, "destination":order.destination, "resource":order.resource, "remaining":order.remaining,
            "assigned":sim.fleet.incoming(&order.destination,order.resource)
        })).collect::<Vec<_>>(),
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
