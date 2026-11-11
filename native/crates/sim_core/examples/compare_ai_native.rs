//! Offline comparison of three planning algorithms on ONE identical native
//! projection. Example:
//! cargo run -p sim_core --example compare_ai_native -- tests/ai_block_b_fixture.json
//! The fixture is a captured-style ECS projection, not a new game engine.
use std::{env,fs,process};
use serde::Deserialize;
use sim_core::strategy::planning::{ActionSpec,GoalSpec,PlanningSnapshot,
    SearchBudget,compare_planners};

#[derive(Deserialize)]
struct Fixture {
    snapshot: PlanningSnapshot,
    goal: GoalSpec,
    actions: Vec<ActionSpec>,
    #[serde(default)]
    max_nodes: Option<u32>,
    #[serde(default)]
    max_depth: Option<usize>,
}

fn main(){
    let Some(path)=env::args().nth(1) else {
        eprintln!("usage: compare_ai_native <fixture.json>");
        process::exit(2);
    };
    let input=fs::read_to_string(&path).unwrap_or_else(|error| {
        eprintln!("cannot read {path}: {error}");process::exit(2)
    });
    let fixture:Fixture=serde_json::from_str(&input).unwrap_or_else(|error| {
        eprintln!("invalid fixture: {error}");process::exit(2)
    });
    let budget=SearchBudget {max_nodes:fixture.max_nodes.unwrap_or(2_000),
        max_depth:fixture.max_depth.unwrap_or(12)};
    let report=compare_planners(&fixture.snapshot,&fixture.goal,&fixture.actions,budget);
    println!("{}",serde_json::to_string_pretty(&report).expect("serializable report"));
    if report.results.iter().any(|x|x.result.status==sim_core::strategy::planning::PlanStatus::Ready && x.validation!="valid_projected_plan") {
        process::exit(1);
    }
}
