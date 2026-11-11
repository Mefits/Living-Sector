use crate::{
    utility::Utility,
    world::{Action, Config, Domain, Fact, Op, State},
};
use std::collections::{BTreeMap, BTreeSet, HashMap, VecDeque};
use telic::planning::{
    action::{ActionBuilder, ActionDef, Strategy},
    belief::{BeliefBuilder, BeliefSet},
    goal::{Goal as TelicGoal, GoalBuilder},
    planner::{CountHeuristic, GoapPlanner, SearchStrategy},
};

pub const METHODS: [&str; 5] = [
    "telic_guided_beam",
    "cranium_utility",
    "cranium_telic_beam",
    "control_beam",
    "htn",
];

#[derive(Debug)]
struct SimulationOnly;
impl Strategy for SimulationOnly {
    fn is_complete(&self) -> bool {
        true
    }
}

fn key(f: Fact) -> String {
    format!("{}:{:?}:{}", f.field, f.op, f.threshold)
}

fn inverse(action: &Action, fact: Fact) -> Option<Option<Fact>> {
    let (set, delta) = action.effect(fact.field);
    if let Some(v) = set {
        return fact.holds_value(v).then_some(None);
    }
    let useful = match fact.op {
        Op::Gte => delta > 0,
        Op::Lte => delta < 0,
        Op::Eq => delta != 0,
    };
    if !useful {
        return None;
    }
    let threshold = fact.threshold.checked_sub(delta)?;
    if fact.op == Op::Eq && threshold < 0 {
        return None;
    }
    Some(Some(Fact { threshold, ..fact }))
}

/// Telic's Boolean GOAP supplies a structural hint. The exact search
/// evaluates the cost and feasibility of every action against live stocks.
struct TelicGuide {
    beliefs: BeliefSet<State>,
    actions: Vec<ActionDef>,
    goals: Vec<TelicGoal>,
}

#[derive(Default)]
struct Hint {
    goal: Option<usize>,
    facts: Vec<(Fact, f64)>,
}
impl TelicGuide {
    fn new(domain: &Domain) -> Self {
        let facts: BTreeSet<_> = domain
            .actions
            .iter()
            .flat_map(|a| a.pre.iter().copied())
            .chain(domain.goals.iter().map(|g| g.fact))
            .collect();
        let persistent: BTreeSet<_> = domain
            .actions
            .iter()
            .flat_map(|a| a.set.iter().map(|&(i, _)| i))
            .filter(|i| {
                !domain
                    .actions
                    .iter()
                    .any(|a| a.delta.iter().any(|(f, _)| f == i))
            })
            .collect();
        let mut beliefs = BeliefSet::new();
        for &fact in &facts {
            beliefs.add(
                BeliefBuilder::new(key(fact))
                    .condition(move |s: &State| fact.holds(s))
                    .build(),
            );
        }
        let actions = domain
            .actions
            .iter()
            .enumerate()
            .filter_map(|(i, a)| {
                let effects: Vec<_> = facts
                    .iter()
                    .copied()
                    .filter(|&f| inverse(a, f).is_some())
                    .collect();
                if effects.is_empty() {
                    return None;
                }
                let mut b = ActionBuilder::new(i.to_string())
                    .cost(a.ticks() as f32)
                    .strategy(SimulationOnly);
                for &f in a.pre.iter().filter(|f| persistent.contains(&f.field)) {
                    b = b.precondition(key(f));
                }
                for f in effects {
                    b = b.effect(key(f));
                }
                Some(b.build())
            })
            .collect();
        let goals = domain
            .goals
            .iter()
            .enumerate()
            .map(|(i, g)| {
                GoalBuilder::new(i.to_string())
                    .priority((g.weight * 100.0) as u32)
                    .desired_effect(key(g.fact))
                    .build()
            })
            .collect();
        Self {
            beliefs,
            actions,
            goals,
        }
    }

    fn hint(&self, d: &Domain, state: &State, selected: Option<usize>) -> Hint {
        let mut goals = self.goals.clone();
        if let Some(i) = selected {
            goals[i].priority = 1_000_000;
        }
        let Some(plan) = GoapPlanner::plan_with(
            &self.beliefs,
            state,
            &self.actions,
            &goals,
            None,
            SearchStrategy::Greedy,
            &CountHeuristic,
        ) else {
            return Hint::default();
        };
        let goal = plan.goal.name.parse::<usize>().expect("goal id");
        let mut facts = BTreeSet::new();
        for action in plan.actions {
            let a = &d.actions[action.parse::<usize>().expect("action id")];
            // A prerequisite such as "factory == 0" is a gate, not progress.
            facts.extend(
                a.pre
                    .iter()
                    .copied()
                    .filter(|f| f.op == Op::Gte && f.threshold > 0),
            );
        }
        let weight = d.goals[goal].weight * 0.15 / facts.len().max(1) as f64;
        Hint {
            goal: Some(goal),
            facts: facts.into_iter().map(|f| (f, weight)).collect(),
        }
    }
}

struct Beam {
    landmarks: Vec<(Fact, f64)>,
    width: usize,
    depth: usize,
    max_nodes: usize,
}
impl Beam {
    fn new(d: &Domain, cfg: &Config) -> Self {
        let mut landmarks = BTreeMap::<Fact, f64>::new();
        let mut frontier: Vec<_> = d.goals.iter().map(|g| (g.fact, g.weight * 0.15)).collect();
        for _ in 0..6 {
            let mut next = Vec::new();
            for (fact, weight) in frontier {
                let value = landmarks.entry(fact).or_default();
                if *value >= weight {
                    continue;
                }
                *value = weight;
                for action in d.actions.iter().filter(|a| inverse(a, fact).is_some()) {
                    for &pre in &action.pre {
                        if pre != fact {
                            next.push((pre, weight * 0.65));
                        }
                    }
                }
            }
            frontier = next;
        }
        Self {
            landmarks: landmarks.into_iter().collect(),
            width: cfg.beam_width,
            depth: cfg.beam_depth,
            max_nodes: cfg.beam_nodes,
        }
    }
    fn rank(&self, d: &Domain, state: &State, ticks: u64, hint: &[(Fact, f64)]) -> f64 {
        d.quality(state) - 0.15 * ticks as f64 / 100.0
            + self
                .landmarks
                .iter()
                .chain(hint)
                .map(|(f, w)| {
                    if f.holds(state) {
                        *w
                    } else if f.op == Op::Gte && f.threshold > 0 {
                        *w * (state[f.field] as f64 / f.threshold as f64).clamp(0.0, 1.0)
                    } else {
                        0.0
                    }
                })
                .sum::<f64>()
    }
    fn plan(
        &self,
        d: &Domain,
        start: &State,
        remaining: usize,
        hint: &[(Fact, f64)],
    ) -> Vec<usize> {
        struct Node {
            state: State,
            ticks: u64,
            path: Vec<usize>,
            rank: f64,
        }
        let mut best_rank = self.rank(d, start, 0, hint);
        let mut best = Vec::new();
        let mut frontier = vec![Node {
            state: start.clone(),
            ticks: 0,
            path: vec![],
            rank: best_rank,
        }];
        let mut visited = HashMap::from([(start.clone(), 0)]);
        let mut nodes = 0;
        for _ in 0..remaining.min(self.depth) {
            let mut next = Vec::new();
            'layer: for node in frontier {
                for (i, a) in d.actions.iter().enumerate().filter(|(i, _)| *i != d.wait) {
                    let Some(state) = a.apply(&node.state) else {
                        continue;
                    };
                    let ticks = node.ticks + u64::from(a.centiticks);
                    if visited.get(&state).is_some_and(|&old| old <= ticks) {
                        continue;
                    }
                    visited.insert(state.clone(), ticks);
                    let rank = self.rank(d, &state, ticks, hint);
                    let mut path = node.path.clone();
                    path.push(i);
                    if rank > best_rank {
                        best_rank = rank;
                        best.clone_from(&path);
                    }
                    next.push(Node {
                        state,
                        ticks,
                        path,
                        rank,
                    });
                    nodes += 1;
                    if nodes >= self.max_nodes {
                        break 'layer;
                    }
                }
            }
            if next.is_empty() || nodes >= self.max_nodes {
                break;
            }
            next.sort_by(|a, b| b.rank.total_cmp(&a.rank));
            next.truncate(self.width);
            frontier = next;
        }
        best
    }
}

enum Engine {
    Telic(TelicGuide, Beam),
    Utility(Utility),
    Hybrid(Utility, TelicGuide, Beam),
    Control(Beam),
    Htn(crate::htn_adapter::Htn),
}
pub struct Planner {
    engine: Engine,
    pending: VecDeque<usize>,
    expected: Option<State>,
}
pub struct Decision {
    pub action: usize,
    pub error: Option<&'static str>,
    pub plan_invalid: bool,
    pub replanned: bool,
    pub guide_facts: usize,
    pub cranium_goal: Option<usize>,
    pub telic_goal: Option<usize>,
    pub comparison: Option<GuideComparison>,
}

impl Decision {
    pub fn idle(action: usize) -> Self {
        Self {
            action,
            error: None,
            plan_invalid: false,
            replanned: false,
            guide_facts: 0,
            cranium_goal: None,
            telic_goal: None,
            comparison: None,
        }
    }
}

pub struct GuideComparison {
    pub baseline: &'static str,
    pub baseline_action: usize,
    pub baseline_telic_goal: Option<usize>,
    pub plan_changed: bool,
    pub action_changed: bool,
}
impl Planner {
    pub fn new(name: &str, domain: &Domain, cfg: &Config) -> Result<Self, String> {
        let engine = match name {
            "telic_guided_beam" => Engine::Telic(TelicGuide::new(domain), Beam::new(domain, cfg)),
            "cranium_utility" => Engine::Utility(Utility::new(domain.actions.len())),
            "cranium_telic_beam" => Engine::Hybrid(
                Utility::new(domain.goals.len()),
                TelicGuide::new(domain),
                Beam::new(domain, cfg),
            ),
            "htn" => Engine::Htn(crate::htn_adapter::Htn::new(domain, cfg)),
            "control_beam" => Engine::Control(Beam::new(domain, cfg)),
            _ => return Err(format!("unknown method {name}")),
        };
        Ok(Self {
            engine,
            pending: VecDeque::new(),
            expected: None,
        })
    }

    pub fn decide(
        &mut self,
        d: &Domain,
        s: &State,
        remaining: usize,
        fallback: usize,
        audit: bool,
    ) -> Decision {
        if self.expected.as_ref() != Some(s) {
            self.pending.clear();
        }
        if let Some(i) = self.pending.pop_front() {
            if let Some(next) = d.actions[i].apply(s) {
                self.expected = Some(next);
                return Decision::idle(i);
            }
            self.pending.clear();
        }
        let mut error = None;
        let mut hint = Hint::default();
        let mut cranium_goal = None;
        let mut baseline = None;
        let mut plan = match &mut self.engine {
            Engine::Telic(telic, beam) => {
                hint = telic.hint(d, s, None);
                let plan = beam.plan(d, s, remaining, &hint.facts);
                if audit {
                    let control = if hint.facts.is_empty() {
                        plan.clone()
                    } else {
                        beam.plan(d, s, remaining, &[])
                    };
                    baseline = Some(("control_beam", control, None));
                }
                plan
            }
            Engine::Utility(u) => {
                let choices: Vec<_> = d
                    .actions
                    .iter()
                    .enumerate()
                    .filter_map(|(i, a)| {
                        a.apply(s)
                            .map(|state| (i, d.quality(&state) - 0.15 * a.ticks()))
                    })
                    .collect();
                let picked = u.select(&choices);
                if picked.is_none() && !choices.is_empty() {
                    error = Some("cranium_no_decision");
                }
                picked.into_iter().collect()
            }
            Engine::Hybrid(u, telic, beam) => {
                let goals: Vec<_> = d
                    .goals
                    .iter()
                    .enumerate()
                    .filter(|(_, g)| !g.fact.holds(s))
                    .map(|(i, g)| (i, g.weight * (1.0 - g.satisfaction(s))))
                    .collect();
                cranium_goal = u.select(&goals);
                if cranium_goal.is_none() && !goals.is_empty() {
                    error = Some("cranium_no_goal");
                }
                hint = telic.hint(d, s, cranium_goal);
                let plan = beam.plan(d, s, remaining, &hint.facts);
                if audit {
                    let unguided_by_utility = telic.hint(d, s, None);
                    let telic_only = if unguided_by_utility.facts == hint.facts {
                        plan.clone()
                    } else {
                        beam.plan(d, s, remaining, &unguided_by_utility.facts)
                    };
                    baseline = Some(("telic_guided_beam", telic_only, unguided_by_utility.goal));
                }
                plan
            }
            Engine::Control(b) => b.plan(d, s, remaining, &[]),
            Engine::Htn(h) => h.plan(d, s, remaining),
        };
        let had_plan = !plan.is_empty();
        let mut state = s.clone();
        let mut valid = 0;
        for &i in plan.iter().take(remaining) {
            let Some(next) = d.actions[i].apply(&state) else {
                break;
            };
            state = next;
            valid += 1;
        }
        let plan_invalid = valid < plan.len().min(remaining);
        plan.truncate(valid);
        let selected = plan.first().copied().unwrap_or(fallback);
        let comparison = baseline.map(|(baseline, baseline_plan, baseline_telic_goal)| {
            let baseline_action = baseline_plan.first().copied().unwrap_or(fallback);
            GuideComparison {
                baseline,
                baseline_action,
                baseline_telic_goal,
                plan_changed: baseline_plan != plan,
                action_changed: baseline_action != selected,
            }
        });
        if error.is_none() {
            error = if had_plan && valid == 0 {
                Some("invalid_plan_head")
            } else if !had_plan && d.goals.iter().any(|g| !g.fact.holds(s)) {
                Some("no_plan_or_improvement")
            } else {
                None
            };
        }
        self.pending = plan.into_iter().skip(1).collect();
        self.expected = d.actions[selected].apply(s);
        Decision {
            action: selected,
            error,
            plan_invalid,
            replanned: true,
            guide_facts: hint.facts.len(),
            cranium_goal,
            telic_goal: hint.goal,
            comparison,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::Goal;

    #[test]
    fn numeric_planners_require_replenishment_between_spends() {
        let fact = |field| Fact {
            field,
            op: Op::Gte,
            threshold: 1,
        };
        let make = |id: &str, pre, delta, set| Action {
            id: id.into(),
            centiticks: 100,
            pre,
            delta,
            set,
        };
        let mut d = Domain {
            fields: ["stock", "intermediate", "goal", "source"]
                .map(String::from)
                .to_vec(),
            actions: vec![
                make("stage", vec![fact(0)], vec![(0, -1)], vec![(1, 1)]),
                make(
                    "finish",
                    vec![fact(0), fact(1)],
                    vec![(0, -1)],
                    vec![(2, 1)],
                ),
                make("wait", vec![], vec![], vec![]),
            ],
            goals: vec![Goal {
                fact: fact(2),
                weight: 100.0,
            }],
            wait: 2,
        };
        let cfg = Config::default();
        let start = vec![1, 0, 0, 1];
        let replay = |d: &Domain, path: Vec<usize>| {
            let mut state = start.clone();
            for i in path {
                state = d.actions[i]
                    .apply(&state)
                    .expect("numeric path must be executable");
            }
            state
        };
        for replenishable in [false, true] {
            if replenishable {
                d.actions.push(make(
                    "replenish",
                    vec![fact(3)],
                    vec![(3, -1), (0, 1)],
                    vec![],
                ));
            }
            let telic = TelicGuide::new(&d);
            let beam = Beam::new(&d, &cfg);
            let hints = telic.hint(&d, &start, None);
            let guided = beam.plan(&d, &start, 3, &hints.facts);
            let htn = crate::htn_adapter::Htn::new(&d, &cfg).plan(&d, &start, 3);
            assert_eq!(fact(2).holds(&replay(&d, guided)), replenishable);
            assert_eq!(fact(2).holds(&replay(&d, htn)), replenishable);
        }
    }
}
