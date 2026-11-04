use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    Mine,
    Warehouse,
    Smelter,
    Repair,
    Observation,
    Yard,
    Gas,
    Refinery,
    Solar,
    Depot,
    PatrolBase,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Site {
    Earth,
    Mars,
    Belt,
    Jupiter,
    Outer,
    Solar,
}

impl Site {
    pub fn label(self) -> &'static str {
        match self {
            Self::Earth => "орбита Земли",
            Self::Mars => "орбита Марса",
            Self::Belt => "пояс астероидов",
            Self::Jupiter => "орбита Юпитера",
            Self::Outer => "внешний сектор",
            Self::Solar => "околосолнечная зона",
        }
    }
}

#[derive(Clone, Copy)]
pub struct Spec {
    pub kind: Kind,
    pub name: &'static str,
    pub metal: u32,
    pub seconds: f64,
    pub sites: &'static [Site],
    pub enabled: bool,
}

use Kind::*;
use Site::{Belt, Earth, Jupiter, Mars, Outer};
const LOCAL: &[Site] = &[Earth, Mars, Belt, Jupiter, Outer];
pub const CATALOG: &[Spec] = &[
    Spec {
        kind: Mine,
        name: "Рудный аванпост",
        metal: 32,
        seconds: 16.0,
        sites: &[Mars, Belt],
        enabled: true,
    },
    Spec {
        kind: Warehouse,
        name: "Грузовой склад",
        metal: 16,
        seconds: 10.0,
        sites: LOCAL,
        enabled: true,
    },
    Spec {
        kind: Smelter,
        name: "Плавильня",
        metal: 24,
        seconds: 16.0,
        sites: LOCAL,
        enabled: true,
    },
    Spec {
        kind: Repair,
        name: "Ремонтный док",
        metal: 16,
        seconds: 12.0,
        sites: LOCAL,
        enabled: true,
    },
    Spec {
        kind: Observation,
        name: "Станция наблюдения",
        metal: 12,
        seconds: 9.0,
        sites: LOCAL,
        enabled: true,
    },
    Spec {
        kind: Yard,
        name: "Орбитальная верфь",
        metal: 24,
        seconds: 18.0,
        sites: LOCAL,
        enabled: true,
    },
    Spec {
        kind: Gas,
        name: "Станция сбора летучих веществ",
        metal: 32,
        seconds: 18.0,
        sites: &[Jupiter],
        enabled: false,
    },
    Spec {
        kind: Refinery,
        name: "Топливный завод",
        metal: 32,
        seconds: 18.0,
        sites: LOCAL,
        enabled: false,
    },
    Spec {
        kind: Solar,
        name: "Солнечная электростанция",
        metal: 24,
        seconds: 14.0,
        sites: &[Site::Solar],
        enabled: false,
    },
    Spec {
        kind: Depot,
        name: "Топливное депо",
        metal: 16,
        seconds: 10.0,
        sites: LOCAL,
        enabled: false,
    },
    Spec {
        kind: PatrolBase,
        name: "Патрульная база",
        metal: 24,
        seconds: 14.0,
        sites: LOCAL,
        enabled: false,
    },
];

impl Kind {
    pub fn spec(self) -> &'static Spec {
        CATALOG
            .iter()
            .find(|entry| entry.kind == self)
            .expect("kind in catalogue")
    }

    pub fn id(self) -> &'static str {
        match self {
            Mine => "mining_rig",
            Warehouse => "cargo_warehouse",
            Smelter => "smelter",
            Repair => "repair_dock",
            Observation => "observation_station",
            Yard => "shipyard",
            Gas => "gas_harvester",
            Refinery => "fuel_refinery",
            Kind::Solar => "solar_power_station",
            Depot => "fuel_depot",
            PatrolBase => "patrol_base",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Choice {
    pub kind: Kind,
    pub site: Site,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub struct Work {
    pub choice: Choice,
    pub remaining: f64,
    pub travel: f64,
    pub fuel: u32,
}

impl Work {
    pub fn on_site(self) -> bool {
        self.remaining <= self.travel + self.choice.kind.spec().seconds
    }

    pub fn finished_assembly(self) -> bool {
        self.remaining <= self.travel
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Program {
    pub active: Option<Work>,
    pub built: Vec<Choice>,
    pub decision: Option<String>,
}

impl Program {
    pub fn has(&self, kind: Kind) -> bool {
        self.built.iter().any(|build| build.kind == kind)
    }
}

pub fn choose(
    metal: u32,
    fuel: u32,
    need: impl Fn(Kind, Site) -> f64,
    distance: impl Fn(Site) -> f64,
) -> Option<Choice> {
    CATALOG
        .iter()
        .filter(|spec| spec.enabled && spec.metal <= metal)
        .flat_map(|spec| spec.sites.iter().map(move |&site| (spec, site)))
        .filter_map(|(spec, site)| {
            let distance = distance(site);
            let cost = (distance * 1.15).ceil().max(2.0) as u32 * 2;
            let score = need(spec.kind, site) - distance * 1.8 - spec.metal as f64 * 0.16;
            (cost <= fuel && score > 0.0).then_some((
                score,
                Choice {
                    kind: spec.kind,
                    site,
                },
            ))
        })
        .max_by(|a, b| a.0.total_cmp(&b.0))
        .map(|(_, work)| work)
}
