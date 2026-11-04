use crate::freight::Commodity;
use crate::sim::Sim;
use serde::{Deserialize, Serialize};
use sim_core::economy::recipes::{RECIPES, Recipe};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Industry {
    pub initialized: bool,
    pub plants: BTreeMap<String, Plant>,
    pub deposits: BTreeMap<String, Deposit>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Deposit {
    pub resource: Commodity,
    pub initial: u32,
    pub remaining: u32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Plant {
    pub location: String,
    pub period: u32,
    pub operation: Operation,
    #[serde(default)]
    pub batch: Option<Batch>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Operation {
    Extract { deposit: String, amount: u32 },
    Process { recipe: String },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Batch {
    pub remaining: u32,
    pub duration: u32,
    pub output: Vec<(Commodity, u32)>,
}

impl Plant {
    pub fn recipe(&self) -> Option<&'static Recipe> {
        let Operation::Process { recipe } = &self.operation else {
            return None;
        };
        RECIPES.iter().find(|entry| entry.id == recipe)
    }

    pub fn extract(location: &str, period: u32, amount: u32) -> Self {
        Self {
            location: location.into(),
            period,
            operation: Operation::Extract {
                deposit: location.into(),
                amount,
            },
            batch: None,
        }
    }

    pub fn process(location: &str, period: u32, recipe: &str) -> Self {
        Self {
            location: location.into(),
            period,
            operation: Operation::Process {
                recipe: recipe.into(),
            },
            batch: None,
        }
    }

    pub fn status(&self, sim: &Sim) -> &'static str {
        if let Some(batch) = &self.batch {
            return if batch.remaining == 0 {
                "Ждёт место на складе"
            } else {
                "В работе"
            };
        }
        match &self.operation {
            Operation::Extract { deposit, .. } => {
                let deposit = &sim.industry.deposits[deposit];
                if deposit.remaining == 0 {
                    "Залежь исчерпана"
                } else if sim.room(&self.location, deposit.resource) == 0 {
                    "Склад заполнен"
                } else if sim.wants_output(&self.location, deposit.resource) {
                    "Готовит добычу"
                } else {
                    "Ждёт спрос на сырьё"
                }
            }
            Operation::Process { .. } => {
                let recipe = self.recipe().expect("validated recipe");
                if !sim.can_store_after(&self.location, recipe.outputs, recipe.inputs) {
                    "Ждёт место для выпуска"
                } else if let Some(&(resource, _)) =
                    recipe.inputs.iter().find(|&&(resource, amount)| {
                        sim.production_supply(&self.location, resource) < amount
                    })
                {
                    match resource {
                        Commodity::Ore => "Ждёт руду",
                        Commodity::Fuel => "Ждёт доступное топливо",
                        _ => "Ждёт сырьё",
                    }
                } else {
                    "Готовит партию"
                }
            }
        }
    }
}

impl Industry {
    pub fn valid(&self, sim: &Sim) -> bool {
        self.deposits.values().all(|d| d.remaining <= d.initial)
            && self.plants.values().all(|plant| {
                plant.period > 0
                    && sim.warehouses.contains_key(&plant.location)
                    && match &plant.operation {
                        Operation::Extract { deposit, amount } => {
                            *amount > 0 && self.deposits.contains_key(deposit)
                        }
                        Operation::Process { .. } => plant.recipe().is_some(),
                    }
                    && plant.batch.as_ref().is_none_or(|batch| {
                        batch.duration > 0
                            && batch.remaining <= batch.duration
                            && !batch.output.is_empty()
                            && batch.output.iter().all(|&(_, amount)| amount > 0)
                    })
            })
    }
}
