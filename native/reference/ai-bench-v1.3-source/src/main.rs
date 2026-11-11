mod htn_adapter;
mod planner;
mod utility;
mod world;

use planner::{METHODS, Planner};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    env,
    fs::{self, File},
    io::{BufWriter, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use world::{Config, State, Suite, World};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

#[cfg(windows)]
fn memory() -> (Option<u64>, Option<u64>) {
    use windows_sys::Win32::{
        System::ProcessStatus::{GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS},
        System::Threading::GetCurrentProcess,
    };
    let mut counters: PROCESS_MEMORY_COUNTERS = unsafe { std::mem::zeroed() };
    let len = std::mem::size_of::<PROCESS_MEMORY_COUNTERS>() as u32;
    counters.cb = len;
    let ok = unsafe { GetProcessMemoryInfo(GetCurrentProcess(), &mut counters, len) };
    if ok == 0 {
        (None, None)
    } else {
        (
            Some(counters.WorkingSetSize as u64),
            Some(counters.PeakWorkingSetSize as u64),
        )
    }
}
#[cfg(target_os = "linux")]
fn memory() -> (Option<u64>, Option<u64>) {
    let status = fs::read_to_string("/proc/self/status").unwrap_or_default();
    let bytes = |name: &str| {
        status
            .lines()
            .find_map(|l| l.strip_prefix(name))
            .and_then(|l| l.split_whitespace().next())
            .and_then(|n| n.parse::<u64>().ok())
            .map(|n| n * 1024)
    };
    (bytes("VmRSS:"), bytes("VmHWM:"))
}
#[cfg(not(any(windows, target_os = "linux")))]
fn memory() -> (Option<u64>, Option<u64>) {
    (None, None)
}

fn round(v: f64) -> f64 {
    (v * 1000.0).round() / 1000.0
}
fn ns(t: Instant) -> u64 {
    t.elapsed().as_nanos().min(u128::from(u64::MAX)) as u64
}
fn named<'a>(world: &'a World, state: &State) -> indexmap::IndexMap<&'a str, i64> {
    world
        .domain
        .fields
        .iter()
        .map(String::as_str)
        .zip(state.iter().copied())
        .collect()
}
fn read_inputs() -> Result<(Suite, Config)> {
    let suite: Suite = serde_json::from_slice(&fs::read("scenarios.json")?)?;
    let config: Config = serde_json::from_slice(&fs::read("config.json")?)?;
    config.validate()?;
    if suite.scenarios.len() != 3 {
        return Err("expected the three archived scenarios".into());
    }
    Ok((suite, config))
}
fn trace_line(trace: &mut BufWriter<File>, data: Value) -> Result<()> {
    serde_json::to_writer(&mut *trace, &data)?;
    trace.write_all(b"\n")?;
    trace.flush()?;
    Ok(())
}

fn digest_bytes(digest: &mut u64, bytes: &[u8]) {
    for &byte in bytes {
        *digest = (*digest ^ u64::from(byte)).wrapping_mul(0x100000001b3);
    }
}

fn worker(args: &[String]) -> Result<()> {
    if args.len() != 9 {
        return Err("invalid worker arguments".into());
    }
    let method = &args[1];
    let world_index: usize = args[2].parse()?;
    let seed = if args[3] == "base" {
        None
    } else {
        Some(args[3].parse::<u64>()?)
    };
    let blind = args[4] == "blind";
    let limit: usize = args[5].parse()?;
    let trace = &args[6];
    let dyson_only = args[7] == "dyson";
    let audit = args[8] == "audit";
    let (suite, cfg) = read_inputs()?;
    let mut source = suite
        .scenarios
        .get(world_index)
        .ok_or("unknown scenario")?
        .clone();
    if dyson_only {
        source.dyson_only()?;
    }
    let dyson_index = source
        .dyson_goal_position()
        .ok_or("scenario has no Dyson objective")?;
    let world = World::new(&source, world_index, seed, &cfg, blind)?;
    let domain = &world.domain;
    let dyson = domain.goals[dyson_index].fact;
    let steps = if limit == 0 {
        world.steps
    } else {
        world.steps.min(limit)
    };
    let start_rss = memory().0;
    let start = Instant::now();
    let mut planner = Planner::new(method, domain, &cfg)?;
    let setup_ns = ns(start);
    let mut trace = BufWriter::new(File::create(trace)?);
    let mut state = world.state.clone();
    trace_line(
        &mut trace,
        json!({"record":"start","scenario":world.id,"name":world.name,"method":method,"seed":seed,
        "blind":blind,"audit_mode":audit,"profile":if dyson_only {"dyson"} else {"portfolio"},"steps":steps,"initial_state":named(&world,&state),
        "action_ticks":domain.actions.iter().map(|a| (a.id.as_str(),a.ticks())).collect::<indexmap::IndexMap<_,_>>()}),
    )?;
    let mut ticks = 0u64;
    let mut trajectory = 0.0;
    let mut timings = Vec::with_capacity(steps);
    let mut invalid = 0usize;
    let mut rejected = 0usize;
    let mut replans = 0usize;
    let mut waits = 0usize;
    let mut guided_replans = 0;
    let mut audit_replans = 0;
    let mut changed_plans = 0;
    let mut changed_actions = 0;
    let mut blocked_turns = 0;
    let mut first_blocked_step = None;
    let mut action_digest = 0xcbf29ce484222325;
    let mut first_dyson = dyson.holds(&state).then_some(0);
    let mut dyson_ticks = first_dyson.map(|_| 0.0);

    let mut errors: BTreeMap<&str, usize> = BTreeMap::new();
    let goal_name = |i: usize| &domain.fields[domain.goals[i].fact.field];
    for step in 0..steps {
        let events = world.inject(step, &mut state);
        let mut action_id = None;
        let mut valid = None;
        let mut planning_ns = None;
        let mut comparison = None;
        let decision = if let Some(fallback) = domain.fallback_action(&state) {
            let decision = if dyson_only && dyson.holds(&state) && fallback == domain.wait {
                planner::Decision::idle(domain.wait)
            } else {
                let start = Instant::now();
                let decision = planner.decide(domain, &state, steps - step, fallback, audit);
                let elapsed = ns(start);
                planning_ns = Some(elapsed);
                timings.push(elapsed);
                decision
            };
            let action = &domain.actions[decision.action];
            action_id = Some(action.id.as_str());
            if let Some(next) = action.apply(&state) {
                valid = Some(true);
                state = next;
            } else {
                valid = Some(false);
                invalid += 1;
                *errors.entry("invalid_world_transition").or_default() += 1;
            }
            if let Some(error) = decision.error {
                *errors.entry(error).or_default() += 1;
            }
            if let Some(check) = &decision.comparison {
                audit_replans += 1;
                changed_plans += usize::from(check.plan_changed);
                changed_actions += usize::from(check.action_changed);
                comparison = Some(json!({
                    "baseline":check.baseline,"baseline_action":domain.actions[check.baseline_action].id,
                    "baseline_telic_goal":check.baseline_telic_goal.map(goal_name),
                    "plan_changed":check.plan_changed,"action_changed":check.action_changed
                }));
            }
            rejected += usize::from(decision.plan_invalid);
            replans += usize::from(decision.replanned);
            guided_replans += usize::from(decision.guide_facts > 0);
            waits += usize::from(decision.action == domain.wait);
            ticks += u64::from(action.centiticks);
            digest_bytes(&mut action_digest, &[1]);
            digest_bytes(&mut action_digest, action.id.as_bytes());
            digest_bytes(&mut action_digest, &[0]);
            Some(decision)
        } else {
            blocked_turns += 1;
            first_blocked_step.get_or_insert(step + 1);
            // The turn still elapses. Preserve the archive's wait-time penalty.
            ticks += u64::from(domain.actions[domain.wait].centiticks);
            digest_bytes(&mut action_digest, &[0]);
            None
        };
        if first_dyson.is_none() && dyson.holds(&state) {
            first_dyson = Some(step + 1);
            dyson_ticks = Some(ticks as f64 / 100.0);
        }
        let quality = domain.quality(&state);
        trajectory += quality;
        trace_line(
            &mut trace,
            json!({"record":"step","step":step,"events":events,"action":action_id,"world_blocked":decision.is_none(),
            "valid":valid,"error":decision.as_ref().and_then(|d| d.error),
            "plan_invalid":decision.as_ref().is_some_and(|d| d.plan_invalid),
            "replanned":decision.as_ref().is_some_and(|d| d.replanned),
            "guide_facts":decision.as_ref().map_or(0, |d| d.guide_facts),
            "cranium_goal":decision.as_ref().and_then(|d| d.cranium_goal).map(goal_name),
            "telic_goal":decision.as_ref().and_then(|d| d.telic_goal).map(goal_name),"audit":comparison,
            "planning_ns":planning_ns,"ticks":ticks as f64 / 100.0,"quality":round(quality),"state":named(&world,&state)}),
        )?;
    }
    let total_ns: u64 = timings.iter().sum();
    timings.sort_unstable();
    let calls = timings.len();
    let median_ns = (calls > 0).then(|| timings[(calls - 1) / 2]);
    let p95_ns = (calls > 0).then(|| timings[(calls * 95).div_ceil(100) - 1]);
    let final_quality = domain.quality(&state);
    let reached = domain.goals.iter().filter(|g| g.fact.holds(&state)).count();
    let reached_weight: f64 = domain
        .goals
        .iter()
        .filter(|g| g.fact.holds(&state))
        .map(|g| g.weight)
        .sum();
    let goals: Vec<_> = domain
        .goals
        .iter()
        .map(|g| {
            json!({
                "field":domain.fields[g.fact.field],"met":g.fact.holds(&state),
                "target":g.fact.threshold,"actual":state[g.fact.field],"weight":g.weight,
            })
        })
        .collect();
    let peak = memory().1;
    let output = json!({"status":"complete","method":method,"scenario":world.id,"seed":seed,"blind":blind,
        "quality":{"score":round(final_quality-0.15*ticks as f64 / 100.0),"trajectory_mean":round(trajectory/steps as f64),
            "goals_met":reached,"goals_total":domain.goals.len(),"weight_met":reached_weight,"goals":goals,
            "ticks":ticks as f64 / 100.0,"decisions":steps-blocked_turns,"waits":waits},
        "execution":{"turns":steps,"blocked_turns":blocked_turns,"first_blocked_step":first_blocked_step,
            "action_trace_fnv1a64":format!("{action_digest:016x}")},
        "dyson":{"achieved":dyson.holds(&state),"first_step":first_dyson,"ticks_to_goal":dyson_ticks,
            "passed":dyson.holds(&state) && invalid==0, "step_budget":steps},
        "planning":{"setup_ns":setup_ns,"calls":calls,"replans":replans,"guided_replans":guided_replans,"total_ns":total_ns,
            "median_ns":median_ns,"p95_ns":p95_ns,"max_ns":timings.last()},
        "audit":audit.then(|| json!({"compared_replans":audit_replans,"changed_plans":changed_plans,"changed_first_actions":changed_actions})),
        "memory":{"baseline_working_set_bytes":start_rss,"peak_process_working_set_bytes":peak},
        "errors":{"invalid_actions":invalid,"rejected_plan_suffixes":rejected,"decision_events":errors}});
    println!("{}", serde_json::to_string(&output)?);
    Ok(())
}

struct Case<'a> {
    method: &'a str,
    scenario: &'a str,
    index: usize,
    seed: Option<u64>,
    blind: bool,
    limit: usize,
    dyson: bool,
    audit: bool,
}
fn execute_case(case: &Case<'_>, dir: &Path, timeout: u64) -> Result<Value> {
    let seed_arg = case
        .seed
        .map(|n| n.to_string())
        .unwrap_or_else(|| "base".into());
    let suffix = if case.blind { "-blind" } else { "" };
    let label = format!("{}-{}-{}{}", case.scenario, case.method, seed_arg, suffix);
    let trace = dir.join("trajectories").join(format!("{label}.jsonl"));
    let stdout = dir.join(format!("{label}.tmp"));
    let stderr = dir.join("trajectories").join(format!("{label}.stderr.txt"));
    print!("{} ... ", label);
    std::io::stdout().flush()?;
    let start = Instant::now();
    let mut child = Command::new(env::current_exe()?)
        .arg("--worker")
        .arg(case.method)
        .arg(case.index.to_string())
        .arg(&seed_arg)
        .arg(if case.blind { "blind" } else { "original" })
        .arg(case.limit.to_string())
        .arg(&trace)
        .arg(if case.dyson { "dyson" } else { "portfolio" })
        .arg(if case.audit { "audit" } else { "normal" })
        .stdout(File::create(&stdout)?)
        .stderr(File::create(&stderr)?)
        .stdin(Stdio::null())
        .spawn()?;
    let mut timed_out = false;
    let status = loop {
        if let Some(status) = child.try_wait()? {
            break status;
        }
        if start.elapsed() >= Duration::from_secs(timeout) {
            timed_out = true;
            let _ = child.kill();
            break child.wait()?;
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    let mut result: Value = if !timed_out && status.success() {
        match serde_json::from_slice(&fs::read(&stdout)?) {
            Ok(v) => v,
            Err(e) => json!({"status":"bad_worker_output","error":e.to_string()}),
        }
    } else {
        json!({"status":if timed_out { "timeout" } else { "worker_error" },"exit_code":status.code()})
    };
    fs::remove_file(stdout)?;
    result["method"] = json!(case.method);
    result["scenario"] = json!(case.scenario);
    result["seed"] = json!(case.seed);
    result["blind"] = json!(case.blind);
    result["wall_ms"] = json!(round(start.elapsed().as_secs_f64() * 1000.0));
    result["trajectory_file"] = if trace.exists() {
        json!(format!("trajectories/{label}.jsonl"))
    } else {
        Value::Null
    };
    if fs::metadata(&stderr)?.len() == 0 {
        fs::remove_file(stderr)?;
    } else {
        result["stderr_file"] = json!(format!("trajectories/{label}.stderr.txt"));
    }
    if case.dyson && result["status"] == "complete" {
        if result["dyson"]["passed"] == true {
            println!("Dyson reached at step {}", result["dyson"]["first_step"]);
        } else {
            println!("Dyson not reached within budget or invalid actions recorded");
        }
    } else {
        println!("{}", result["status"].as_str().unwrap_or("unknown"));
    }
    Ok(result)
}
fn coordinator(args: &[String]) -> Result<bool> {
    if args.iter().any(|a| a == "--help" || a == "-h") {
        println!(
            "ls-ai-bench [--smoke] [--dyson] [--audit] [--method NAME] [--scenario ID]\nMethods: {}\nDefault: archived scenarios plus optional config.json variants. --smoke: first three decisions of one world. --dyson: only the Dyson completion goal. --audit: compare guided Beam plans with a same-state baseline, including shadow search in timings.",
            METHODS.join(", ")
        );
        return Ok(true);
    }
    let mut smoke = false;
    let mut dyson = false;
    let mut audit = false;
    let mut method = None;
    let mut scenario = None;
    let mut params = args.iter();
    while let Some(arg) = params.next() {
        match arg.as_str() {
            "--smoke" => smoke = true,
            "--dyson" => dyson = true,
            "--audit" => audit = true,
            "--method" => method = Some(params.next().ok_or("missing --method value")?.as_str()),
            "--scenario" => {
                scenario = Some(params.next().ok_or("missing --scenario value")?.as_str())
            }
            _ => return Err(format!("unknown option {arg}; use --help").into()),
        }
    }
    let (suite, cfg) = read_inputs()?;
    if method.is_some_and(|m| !METHODS.contains(&m))
        || scenario.is_some_and(|s| !suite.scenarios.iter().any(|w| w.id == s))
    {
        return Err("unknown method or scenario; use --help".into());
    }
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    let dir = PathBuf::from("results").join(format!("{stamp}-{}", std::process::id()));
    fs::create_dir_all(dir.join("trajectories"))?;
    let mut output = json!({"bench_version":env!("CARGO_PKG_VERSION"),"suite":"AI Decision Bench 0.4","smoke":smoke,"audit":audit,
        "profile":if dyson {"dyson"} else {"portfolio"},
        "libraries":{"htn":"0.2.1","telic":"0.1.0","cranium":"0.3.0","cranium-core":"0.3.0","bevy_ecs":"0.19.1"},
        "archived_scenarios_sha256":"f09755b9718404d0f5c65fbc7099837a9239ac9253290465084eeda8b457aa65",
        "config":cfg,"runs":[]});
    let mut failed = 0;
    let mut dyson_passes = 0;
    let seeds: Vec<Option<u64>> = std::iter::once(None)
        .chain(cfg.extra_seeds.iter().copied().map(Some))
        .collect();
    for (index, world) in suite
        .scenarios
        .iter()
        .enumerate()
        .filter(|(i, w)| scenario.map_or(!smoke || *i == 0, |s| w.id == s))
    {
        for &seed in seeds.iter().take(if smoke { 1 } else { seeds.len() }) {
            for blind in [false, true]
                .into_iter()
                .take(if cfg.blind && !smoke { 2 } else { 1 })
            {
                for method in METHODS
                    .into_iter()
                    .filter(|m| method.is_none_or(|s| s == *m))
                {
                    let case = Case {
                        method,
                        scenario: &world.id,
                        index,
                        seed,
                        blind,
                        limit: if smoke { 3 } else { 0 },
                        dyson,
                        audit,
                    };
                    let row = execute_case(&case, &dir, cfg.timeout_seconds)?;
                    failed += usize::from(row["status"] != "complete");
                    dyson_passes += usize::from(row["dyson"]["passed"] == true);
                    output["runs"].as_array_mut().unwrap().push(row);
                    fs::write(dir.join("summary.json"), serde_json::to_vec(&output)?)?;
                }
            }
        }
    }
    println!(
        "Summary: {}  |  failed cases: {failed}",
        dir.join("summary.json").display()
    );
    if dyson && !smoke {
        println!(
            "Dyson passed: {dyson_passes}/{}",
            output["runs"].as_array().unwrap().len()
        );
    }
    Ok(failed == 0)
}
fn main() {
    let args: Vec<_> = env::args().skip(1).collect();
    let result = if args.first().is_some_and(|a| a == "--worker") {
        worker(&args).map(|_| true)
    } else {
        coordinator(&args)
    };
    match result {
        Ok(true) => {}
        Ok(false) => std::process::exit(1),
        Err(error) => {
            eprintln!("Bench error: {error}");
            std::process::exit(2);
        }
    }
}
