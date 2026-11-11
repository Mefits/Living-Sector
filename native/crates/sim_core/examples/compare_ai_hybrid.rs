//! Same actual Genesis-style projection used by Block B, with Block C hybrid
//! role tracing. NO live server, orders, database writes, or synthetic world.
//! cargo run -p sim_core --example compare_ai_hybrid -- tests/ai_block_b_fixture.json
use std::{env, fs, process};
use serde::Deserialize;
use sim_core::strategy::planning::{ActionSpec,GoalSpec,HybridPlanner,
    HybridPreferences,PlanningSnapshot,PlanStatus,SearchBudget,validate_plan};

#[derive(Deserialize)]
struct Input {
    snapshot:PlanningSnapshot,goal:GoalSpec,actions:Vec<ActionSpec>,
    #[serde(default)] max_nodes:Option<u32>,
    #[serde(default)] max_depth:Option<usize>,
}
fn main(){
    let Some(path)=env::args().nth(1) else {
        eprintln!("usage: compare_ai_hybrid <native-fixture.json>");process::exit(2)
    };
    let input=fs::read_to_string(&path).unwrap_or_else(|error|{
        eprintln!("read {path}: {error}");process::exit(2)
    });
    let fixture:Input=serde_json::from_str(&input).unwrap_or_else(|error|{
        eprintln!("invalid native fixture: {error}");process::exit(2)
    });
    let budget=SearchBudget{max_nodes:fixture.max_nodes.unwrap_or(2_000),
        max_depth:fixture.max_depth.unwrap_or(12)};
    let planner=HybridPlanner{preferences:HybridPreferences::default()};
    let result=planner.decide(&fixture.snapshot,&fixture.goal,&fixture.actions,budget);
    println!("{}",serde_json::to_string_pretty(&result).unwrap());
    if result.result.status!=PlanStatus::Ready ||
        validate_plan(&fixture.snapshot,&fixture.goal,&fixture.actions,&result.result,budget).is_err() {
        eprintln!("hybrid did not produce a valid full plan for the supplied acceptance fixture");
        process::exit(1);
    }
}
