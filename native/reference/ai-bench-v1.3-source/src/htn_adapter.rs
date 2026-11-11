//! Lazy, stateful HTN method generation over the scenario's action catalogue.
//! The upstream crate executes finite Task sequences against its blackboard.
use crate::world::{Action, Config, Domain, Fact, Op, State};
use htn::{ArithmeticOp, ComparisonOp, Condition, Effect, Task, Value};
use std::collections::{BTreeSet, HashMap, HashSet};

fn condition(fields: &[String], fact: Fact) -> Condition {
    let cmp = match fact.op {
        Op::Eq => ComparisonOp::E,
        Op::Gte => ComparisonOp::GTE,
        Op::Lte => ComparisonOp::LTE,
    };
    Condition::compare(
        &fields[fact.field],
        cmp,
        Value::Int(fact.threshold.try_into().expect("archive value fits i32")),
    )
}

fn integer(value: i64) -> Value {
    Value::Int(value.try_into().expect("archive value fits i32"))
}

fn moves_toward(a: &Action, fact: Fact, current: i64) -> bool {
    let (set, delta) = a.effect(fact.field);
    let next = set.unwrap_or_else(|| current.saturating_add(delta));
    let gap = |v: i64| match fact.op {
        Op::Gte => fact.threshold.saturating_sub(v).max(0),
        Op::Lte => v.saturating_sub(fact.threshold).max(0),
        Op::Eq => v.abs_diff(fact.threshold).min(i64::MAX as u64) as i64,
    };
    gap(next) < gap(current)
}

pub struct Htn {
    primitive: Vec<Task>,
    requirements: Vec<Vec<Fact>>,
    producers: Vec<Vec<usize>>,
    max_nodes: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum Work {
    Require(Fact),
    Prepare(usize),
    Apply(usize, Fact),
}

impl Htn {
    pub fn new(d: &Domain, cfg: &Config) -> Self {
        let mut primitive = Vec::with_capacity(d.actions.len());
        let mut requirements = Vec::with_capacity(d.actions.len());
        let mut producers = vec![Vec::new(); d.fields.len()];
        for (i, a) in d.actions.iter().enumerate() {
            let mut needs = a.pre.clone();
            let mut check_nonnegative = Vec::new();
            for (f, list) in producers.iter_mut().enumerate() {
                let (set, delta) = a.effect(f);
                if set.is_some() || delta != 0 {
                    list.push(i);
                }
                if set.is_none() {
                    let check = Fact {
                        field: f,
                        op: Op::Gte,
                        threshold: -delta,
                    };
                    check_nonnegative.push(check);
                    if delta < 0
                        && !needs.iter().any(|p| {
                            p.field == f
                                && matches!(p.op, Op::Gte | Op::Eq)
                                && p.threshold >= -delta
                        })
                    {
                        needs.push(check);
                    }
                }
            }
            let preconditions = needs
                .iter()
                .chain(&check_nonnegative)
                .copied()
                .collect::<BTreeSet<_>>()
                .into_iter()
                .map(|f| condition(&d.fields, f))
                .collect();
            let effects = a
                .delta
                .iter()
                .map(|&(f, v)| Effect::new(&d.fields[f], ArithmeticOp::Add, integer(v)))
                .chain(
                    a.set
                        .iter()
                        .map(|&(f, v)| Effect::new(&d.fields[f], ArithmeticOp::Eq, integer(v))),
                )
                .collect();
            primitive.push(Task::Action {
                preconditions,
                action: i.to_string(),
                effects,
            });
            requirements.push(needs);
        }
        Self {
            primitive,
            requirements,
            producers,
            max_nodes: cfg.htn_nodes,
        }
    }

    pub fn plan(&self, d: &Domain, state: &State, remaining: usize) -> Vec<usize> {
        let mut goals: Vec<_> = d.goals.iter().filter(|g| !g.fact.holds(state)).collect();
        goals.sort_by(|a, b| b.weight.total_cmp(&a.weight));
        let mut nodes = self.max_nodes;
        for g in goals {
            let mut search = Search {
                adapter: self,
                domain: d,
                remaining,
                nodes,
                seen: HashSet::new(),
            };
            let mut path = Vec::new();
            if search.find(state, vec![Work::Require(g.fact)], &mut path) {
                let mut tasks: Vec<_> = path.iter().map(|&i| self.primitive[i].clone()).collect();
                // The original HTN library checks the full ordered sequence
                // against evolving stocks, including the terminal requirement.
                tasks.push(Task::Action {
                    preconditions: vec![condition(&d.fields, g.fact)],
                    action: "done".into(),
                    effects: vec![],
                });
                let root = Task::Sequence {
                    preconditions: vec![],
                    tasks,
                };
                let Ok(mut result) = htn::plan(&root, &blackboard(d, state)) else {
                    continue;
                };
                if result.pop().as_deref() != Some("done") {
                    continue;
                }
                return result
                    .iter()
                    .map(|id| id.parse().expect("native task index"))
                    .collect();
            }
            nodes = search.nodes;
            if nodes == 0 {
                break;
            }
        }
        Vec::new()
    }
}

fn blackboard(d: &Domain, state: &State) -> HashMap<String, Value> {
    d.fields
        .iter()
        .cloned()
        .zip(state.iter().copied().map(integer))
        .collect()
}

struct Search<'a> {
    adapter: &'a Htn,
    domain: &'a Domain,
    remaining: usize,
    nodes: usize,
    seen: HashSet<(State, Vec<Work>, usize)>,
}
impl Search<'_> {
    fn find(&mut self, state: &State, mut todo: Vec<Work>, path: &mut Vec<usize>) -> bool {
        let Some(task) = todo.pop() else {
            return true;
        };
        if self.nodes == 0 || todo.len() > 100 {
            return false;
        }
        self.nodes -= 1;

        match task {
            Work::Require(f) if f.holds(state) => self.find(state, todo, path),
            Work::Require(f) => {
                if path.len() >= self.remaining
                    || todo
                        .iter()
                        .any(|task| matches!(task,Work::Apply(_,target) if *target == f))
                {
                    return false;
                }
                // Ordered HTN methods: each producer is an alternative
                // decomposition into prerequisites, action, and a recheck.
                let mut methods: Vec<_> = self.adapter.producers[f.field]
                    .iter()
                    .copied()
                    .filter(|&i| moves_toward(&self.domain.actions[i], f, state[f.field]))
                    .collect();
                methods.sort_by_key(|&i| {
                    let a = &self.domain.actions[i];
                    let (set, delta) = a.effect(f.field);
                    let next = set.unwrap_or(state[f.field] + delta);
                    (
                        self.adapter.requirements[i]
                            .iter()
                            .filter(|p| !p.holds(state))
                            .count(),
                        !f.holds_value(next),
                        a.centiticks,
                        i,
                    )
                });
                for i in methods {
                    let mut branch = todo.clone();
                    branch.extend([Work::Require(f), Work::Apply(i, f), Work::Prepare(i)]);
                    if self.find(state, branch, path) {
                        return true;
                    }
                }
                false
            }
            Work::Prepare(i) => {
                let a = &self.domain.actions[i];
                let mut missing: Vec<_> = self.adapter.requirements[i]
                    .iter()
                    .copied()
                    .filter(|p| !p.holds(state))
                    .collect();
                // When an external event has made a stock negative, a valid
                // next primitive still has to restore every negative field.
                for (field, &v) in state.iter().enumerate().filter(|&(_, v)| *v < 0) {
                    let (set, delta) = a.effect(field);
                    if set.is_none() && v.saturating_add(delta) < 0 {
                        let f = Fact {
                            field,
                            op: Op::Gte,
                            threshold: -delta,
                        };
                        if !missing.contains(&f) {
                            missing.push(f);
                        }
                    }
                }
                if missing.is_empty() {
                    return self.find(state, todo, path);
                }
                let sig = (state.clone(), todo.clone(), self.remaining - path.len());
                if !self.seen.insert(sig) {
                    return false;
                }
                for f in missing {
                    let mut branch = todo.clone();
                    branch.extend([Work::Prepare(i), Work::Require(f)]);
                    if self.find(state, branch, path) {
                        return true;
                    }
                }
                false
            }
            Work::Apply(i, target) => {
                if target.holds(state) {
                    return self.find(state, todo, path);
                }
                if path.len() >= self.remaining
                    || !moves_toward(&self.domain.actions[i], target, state[target.field])
                {
                    return false;
                }
                if htn::plan(&self.adapter.primitive[i], &blackboard(self.domain, state)).is_err() {
                    return false;
                }
                let Some(next) = self.domain.actions[i].apply(state) else {
                    return false;
                };
                path.push(i);
                if self.find(&next, todo, path) {
                    return true;
                }
                path.pop();
                false
            }
        }
    }
}
