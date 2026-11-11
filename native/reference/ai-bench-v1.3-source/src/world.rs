use indexmap::IndexMap;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

pub type State = Vec<i64>;
type Values = IndexMap<String, i64>;

#[derive(Deserialize)]
pub struct Suite {
    pub scenarios: Vec<ScenarioInput>,
}
#[derive(Clone, Deserialize)]
pub struct ScenarioInput {
    pub id: String,
    pub name: String,
    pub steps: usize,
    state: Values,
    actions: Vec<ActionInput>,
    goals: Vec<GoalInput>,
    #[serde(default)]
    events: Vec<EventInput>,
}
impl ScenarioInput {
    pub fn dyson_goal_position(&self) -> Option<usize> {
        self.goals.iter().position(|goal| goal.field == "dyson")
    }
    pub fn dyson_only(&mut self) -> Result<(), String> {
        self.goals.retain(|goal| goal.field == "dyson");
        if self.goals.len() != 1 {
            return Err(format!("{} must specify one Dyson goal", self.id));
        }
        Ok(())
    }
}
#[derive(Clone, Deserialize)]
struct ActionInput {
    id: String,
    #[serde(default)]
    ticks: u32,
    #[serde(default)]
    pre: IndexMap<String, IndexMap<Op, i64>>,
    #[serde(default)]
    delta: Values,
    #[serde(default)]
    set: Values,
}
#[derive(Clone, Deserialize)]
struct GoalInput {
    field: String,
    target: i64,
    weight: f64,
    #[serde(default)]
    direction: String,
}
#[derive(Clone, Deserialize)]
struct EventInput {
    before_step: usize,
    #[serde(default)]
    set: Values,
    #[serde(default)]
    delta: Values,
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[serde(rename_all = "lowercase")]
pub enum Op {
    Gte,
    Lte,
    Eq,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Fact {
    pub field: usize,
    pub op: Op,
    pub threshold: i64,
}
impl Fact {
    pub fn holds_value(self, value: i64) -> bool {
        match self.op {
            Op::Gte => value >= self.threshold,
            Op::Lte => value <= self.threshold,
            Op::Eq => value == self.threshold,
        }
    }
    pub fn holds(self, state: &State) -> bool {
        self.holds_value(state[self.field])
    }
}
#[derive(Clone)]
pub struct Action {
    pub id: String,
    pub centiticks: u32,
    pub pre: Vec<Fact>,
    pub delta: Vec<(usize, i64)>,
    pub set: Vec<(usize, i64)>,
}
impl Action {
    pub fn ticks(&self) -> f64 {
        f64::from(self.centiticks) / 100.0
    }
    pub fn apply(&self, before: &State) -> Option<State> {
        if !self.pre.iter().all(|p| p.holds(before)) {
            return None;
        }
        let mut state = before.clone();
        for &(field, amount) in &self.delta {
            state[field] = state[field].checked_add(amount)?;
        }
        for &(field, value) in &self.set {
            state[field] = value;
        }
        state.iter().all(|&value| value >= 0).then_some(state)
    }
    pub fn effect(&self, field: usize) -> (Option<i64>, i64) {
        (
            self.set.iter().find(|&&(i, _)| i == field).map(|x| x.1),
            self.delta
                .iter()
                .find(|&&(i, _)| i == field)
                .map_or(0, |x| x.1),
        )
    }
}
pub struct Goal {
    pub fact: Fact,
    pub weight: f64,
}
impl Goal {
    pub fn satisfaction(&self, state: &State) -> f64 {
        let n = state[self.fact.field] as f64;
        let target = self.fact.threshold as f64;
        if self.fact.op == Op::Lte {
            if n <= target {
                1.0
            } else {
                (target / n.max(0.001)).min(1.0)
            }
        } else {
            (n / target.max(0.001)).clamp(0.0, 1.0)
        }
    }
}
pub struct Domain {
    pub fields: Vec<String>,
    pub actions: Vec<Action>,
    pub goals: Vec<Goal>,
    pub wait: usize,
}
impl Domain {
    pub fn fallback_action(&self, state: &State) -> Option<usize> {
        if self.actions[self.wait].apply(state).is_some() {
            Some(self.wait)
        } else {
            self.actions.iter().position(|a| a.apply(state).is_some())
        }
    }

    pub fn quality(&self, s: &State) -> f64 {
        self.goals
            .iter()
            .map(|g| g.weight * g.satisfaction(s))
            .sum()
    }
}
struct Event {
    step: usize,
    set: Vec<(usize, i64)>,
    delta: Vec<(usize, i64)>,
}
pub struct World {
    pub domain: Domain,
    pub state: State,
    pub id: String,
    pub name: String,
    pub steps: usize,
    events: Vec<Event>,
    crisis: Option<(usize, usize, u32)>,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    pub extra_seeds: Vec<u64>,
    pub resource_percent: u32,
    pub action_ticks_percent: u32,
    pub crisis_loss_percent: u32,
    pub blind: bool,
    pub timeout_seconds: u64,
    pub beam_width: usize,
    pub beam_depth: usize,
    pub beam_nodes: usize,
    pub htn_nodes: usize,
}
impl Default for Config {
    fn default() -> Self {
        Self {
            extra_seeds: vec![],
            resource_percent: 20,
            action_ticks_percent: 20,
            crisis_loss_percent: 25,
            blind: false,
            timeout_seconds: 180,
            beam_width: 24,
            beam_depth: 22,
            beam_nodes: 12_000,
            htn_nodes: 50_000,
        }
    }
}
impl Config {
    pub fn validate(&self) -> Result<(), String> {
        if self.extra_seeds.len() > 100
            || self.extra_seeds.iter().collect::<HashSet<_>>().len() != self.extra_seeds.len()
            || self.resource_percent > 50
            || self.action_ticks_percent > 50
            || self.crisis_loss_percent > 50
            || !(1..=3600).contains(&self.timeout_seconds)
            || !(1..=200).contains(&self.beam_width)
            || !(1..=100).contains(&self.beam_depth)
            || !(1..=200_000).contains(&self.beam_nodes)
            || !(1..=500_000).contains(&self.htn_nodes)
        {
            return Err("config.json: expected unique seeds (up to 100), percentages 0..50, timeout 1..3600, beam width 1..200, depth 1..100, beam nodes 1..200000, HTN nodes 1..500000".into());
        }
        Ok(())
    }
}
struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e3779b97f4a7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
        z ^ (z >> 31)
    }
    fn below(&mut self, bound: usize) -> usize {
        (self.next() % bound as u64) as usize
    }
    fn factor(&mut self, pct: u32) -> i64 {
        100 + self.below((2 * pct + 1) as usize) as i64 - i64::from(pct)
    }
    fn vary(&mut self, value: i64, pct: u32) -> i64 {
        (value * self.factor(pct) + 50) / 100
    }
    fn shuffle<T>(&mut self, values: &mut [T]) {
        for i in (1..values.len()).rev() {
            values.swap(i, self.below(i + 1));
        }
    }
}
impl World {
    pub fn new(
        input: &ScenarioInput,
        world_index: usize,
        seed: Option<u64>,
        cfg: &Config,
        blind: bool,
    ) -> Result<Self, String> {
        let index = |key: &str| {
            input
                .state
                .get_index_of(key)
                .ok_or_else(|| format!("unknown state field {key}"))
        };
        let encode = |values: &Values| {
            values
                .iter()
                .map(|(k, &v)| Ok((index(k)?, v)))
                .collect::<Result<Vec<_>, String>>()
        };
        let mut fields: Vec<_> = input.state.keys().cloned().collect();
        let mut state: State = input.state.values().copied().collect();
        let mut actions = Vec::new();
        for a in &input.actions {
            let mut pre = Vec::new();
            for (key, conditions) in &a.pre {
                for (&op, &threshold) in conditions {
                    pre.push(Fact {
                        field: index(key)?,
                        op,
                        threshold,
                    });
                }
            }
            actions.push(Action {
                id: a.id.clone(),
                centiticks: a.ticks.max(1) * 100,
                pre,
                delta: encode(&a.delta)?,
                set: encode(&a.set)?,
            });
        }
        let mut goals = input
            .goals
            .iter()
            .map(|g| {
                Ok(Goal {
                    fact: Fact {
                        field: index(&g.field)?,
                        op: if g.direction == "lte" {
                            Op::Lte
                        } else {
                            Op::Gte
                        },
                        threshold: g.target,
                    },
                    weight: g.weight,
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        let mut events = input
            .events
            .iter()
            .map(|e| {
                Ok(Event {
                    step: e.before_step,
                    delta: encode(&e.delta)?,
                    set: encode(&e.set)?,
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        if input.steps == 0
            || actions.is_empty()
            || goals.is_empty()
            || actions.iter().map(|a| &a.id).collect::<HashSet<_>>().len() != actions.len()
        {
            return Err(format!("invalid world {}", input.id));
        }
        let wait_id = actions
            .iter()
            .position(|a| a.id == "wait")
            .ok_or("missing wait")?;
        let mut wait = wait_id;
        let mut crisis = None;
        if let Some(seed) = seed {
            let mut rng = Rng(seed ^ (world_index as u64).wrapping_mul(0xd6e8feb86659fd93));
            // Large starting stocks are perturbable; zeroes and small capability counters stay fixed.
            let stocks: Vec<_> = state
                .iter()
                .enumerate()
                .filter_map(|(i, &v)| (v >= 4).then_some(i))
                .collect();
            for &i in &stocks {
                state[i] = rng.vary(state[i], cfg.resource_percent);
            }
            for action in &mut actions {
                action.centiticks = (i64::from(action.centiticks)
                    * rng.factor(cfg.action_ticks_percent)
                    / 100) as u32;
            }
            if cfg.crisis_loss_percent > 0 && !stocks.is_empty() {
                let min = input.steps / 4;
                let step = min + rng.below((input.steps * 3 / 4 - min).max(1));
                crisis = Some((
                    step,
                    stocks[rng.below(stocks.len())],
                    cfg.crisis_loss_percent,
                ));
            }
        }
        if blind {
            let mut rng = Rng(seed.unwrap_or(0) ^ 0x97ac4f7a3182ac67);
            let mut order: Vec<usize> = (0..fields.len()).collect();
            rng.shuffle(&mut order);
            let mut index_map = vec![0; fields.len()];
            for (new, &old) in order.iter().enumerate() {
                index_map[old] = new;
            }
            state = order.iter().map(|&old| state[old]).collect();
            fields = (0..fields.len()).map(|new| format!("f{new:03}")).collect();
            for a in &mut actions {
                for f in &mut a.pre {
                    f.field = index_map[f.field];
                }
                for (i, _) in a.delta.iter_mut().chain(&mut a.set) {
                    *i = index_map[*i];
                }
            }
            for g in &mut goals {
                g.fact.field = index_map[g.fact.field];
            }
            for e in &mut events {
                for (i, _) in e.delta.iter_mut().chain(&mut e.set) {
                    *i = index_map[*i];
                }
            }
            if let Some((_, i, _)) = &mut crisis {
                *i = index_map[*i];
            }
            for (i, a) in actions.iter_mut().enumerate() {
                a.id = format!("a{i:03}");
            }
            let wait_key = actions[wait_id].id.clone();
            rng.shuffle(&mut actions);
            wait = actions.iter().position(|a| a.id == wait_key).unwrap();
        }
        Ok(Self {
            domain: Domain {
                fields,
                actions,
                goals,
                wait,
            },
            id: input.id.clone(),
            name: input.name.clone(),
            state,
            steps: input.steps,
            events,
            crisis,
        })
    }

    pub fn inject(&self, step: usize, state: &mut State) -> Vec<String> {
        let mut fired = Vec::new();
        for event in self.events.iter().filter(|e| e.step == step) {
            for &(i, v) in &event.set {
                state[i] = v;
            }
            for &(i, v) in &event.delta {
                state[i] += v;
            }
            fired.push("archive_event".into());
        }
        if let Some((_, field, pct)) = self.crisis.filter(|e| e.0 == step) {
            let lost = state[field].max(0) * i64::from(pct) / 100;
            state[field] -= lost;
            fired.push(format!(
                "extra_crisis:{}:-{lost}",
                self.domain.fields[field]
            ));
        }
        fired
    }
}
