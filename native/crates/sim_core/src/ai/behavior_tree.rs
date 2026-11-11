//! Behavior tree engine — generic over a domain action type.
//!
//! Once the utility layer selects a goal (e.g. `trade_run`), a behavior tree
//! handles step-by-step execution. The tree resumes where it left off across
//! ticks via `Sequence`'s saved index.
//!
//! ## Node types
//! - `Sequence` — run children in order; fail on first failure; resume on `Running`
//! - `Selector` — try children in order; succeed on first success; always restart
//! - `Condition` — predicate over the `Blackboard`; `Success` or `Failure` instantly
//! - `Action(A)` — domain-specific leaf; the tick caller supplies a dispatch
//!   closure that knows how to execute `A`
//!
//! ## Why generic over `A`?
//!
//! In Phase 4 we tried `Action { run: fn(&mut Blackboard) -> BtStatus }`. That
//! only works for parameter-free actions because Rust `fn` pointers can't
//! capture state. A `travel_to("earth-station")` action needs the location
//! baked in. Making `BtNode` generic over an action type lets us express
//! `Action(ShipAction::Travel { destination: "earth-station" })` — the action
//! enum carries parameters as data. The caller provides a dispatch function
//! per-tick that has full world access and knows how to interpret the variant.
//!
//! `A` must implement `Clone + Debug` so the tree can be stored on the agent
//! and inspected for diagnostics.

use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BtStatus {
    Running,
    Success,
    Failure,
}

/// Scratch value types for the blackboard (ephemeral per-BT-run data).
#[derive(Debug, Clone)]
pub enum BbValue {
    Int(i64),
    Float(f32),
    Bool(bool),
    Str(String),
}

/// Per-tick scratch data shared across BT nodes during a single tick's walk.
/// Not persisted — the BT's persistent state is the `Sequence.index` field.
#[derive(Debug, Default)]
pub struct Blackboard {
    pub scratch: HashMap<&'static str, BbValue>,
}

impl Blackboard {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set(&mut self, key: &'static str, val: BbValue) {
        self.scratch.insert(key, val);
    }

    pub fn get(&self, key: &'static str) -> Option<&BbValue> {
        self.scratch.get(key)
    }

    pub fn get_bool(&self, key: &'static str) -> bool {
        matches!(self.scratch.get(key), Some(BbValue::Bool(true)))
    }
}

pub type ConditionFn = fn(&Blackboard) -> bool;

/// A behavior-tree node generic over the action type `A`.
///
/// `A` is typically a domain-specific enum (e.g. `ShipAction`) with parameter
/// data on each variant. The tick caller provides a dispatch closure that
/// matches on the variant and performs the real work against world state.
#[derive(Clone)]
pub enum BtNode<A: Clone + std::fmt::Debug> {
    Sequence {
        children: Vec<BtNode<A>>,
        /// Index of the child currently executing. Resets to 0 on success or failure.
        index: usize,
    },
    Selector {
        children: Vec<BtNode<A>>,
    },
    Condition {
        name: &'static str,
        check: ConditionFn,
    },
    Action(A),
}

impl<A: Clone + std::fmt::Debug> std::fmt::Debug for BtNode<A> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BtNode::Sequence { children, index } => {
                write!(f, "Sequence(idx={}, {} children)", index, children.len())
            }
            BtNode::Selector { children } => {
                write!(f, "Selector({} children)", children.len())
            }
            BtNode::Condition { name, .. } => write!(f, "Condition({name})"),
            BtNode::Action(a) => write!(f, "Action({a:?})"),
        }
    }
}

impl<A: Clone + std::fmt::Debug> BtNode<A> {
    // --- Constructors ---

    pub fn sequence(children: Vec<BtNode<A>>) -> Self {
        BtNode::Sequence { children, index: 0 }
    }

    pub fn selector(children: Vec<BtNode<A>>) -> Self {
        BtNode::Selector { children }
    }

    pub fn condition(name: &'static str, check: ConditionFn) -> Self {
        BtNode::Condition { name, check }
    }

    pub fn action(action: A) -> Self {
        BtNode::Action(action)
    }

    // --- Tick ---

    /// Advance the tree by one step.
    ///
    /// `dispatch` is a caller-provided closure that knows how to execute a
    /// leaf action. It has full mutable access to whatever state the caller
    /// captured — ship components, command buffer, etc.
    pub fn tick<F>(&mut self, bb: &mut Blackboard, dispatch: &mut F) -> BtStatus
    where
        F: FnMut(&A, &mut Blackboard) -> BtStatus,
    {
        match self {
            BtNode::Action(a) => dispatch(a, bb),

            BtNode::Condition { check, .. } => {
                if check(bb) {
                    BtStatus::Success
                } else {
                    BtStatus::Failure
                }
            }

            BtNode::Sequence { children, index } => {
                if *index >= children.len() {
                    *index = 0;
                    return BtStatus::Success;
                }
                let status = children[*index].tick(bb, dispatch);
                match status {
                    BtStatus::Success => {
                        *index += 1;
                        if *index >= children.len() {
                            *index = 0;
                            BtStatus::Success
                        } else {
                            BtStatus::Running
                        }
                    }
                    BtStatus::Running => BtStatus::Running,
                    BtStatus::Failure => {
                        *index = 0;
                        BtStatus::Failure
                    }
                }
            }

            BtNode::Selector { children } => {
                for child in children.iter_mut() {
                    match child.tick(bb, dispatch) {
                        BtStatus::Success => return BtStatus::Success,
                        BtStatus::Running => return BtStatus::Running,
                        BtStatus::Failure => continue,
                    }
                }
                BtStatus::Failure
            }
        }
    }

    /// Return the currently active leaf action (for debugging/UI).
    pub fn current_action(&self) -> Option<String> {
        match self {
            BtNode::Action(a) => Some(format!("{a:?}")),
            BtNode::Condition { name, .. } => Some((*name).to_string()),
            BtNode::Sequence { children, index } => {
                children.get(*index).and_then(|c| c.current_action())
            }
            BtNode::Selector { children } => {
                children.first().and_then(|c| c.current_action())
            }
        }
    }

    /// Reset sequence counters. Call when switching goals.
    pub fn reset(&mut self) {
        if let BtNode::Sequence { index, children } = self {
            *index = 0;
            for c in children.iter_mut() {
                c.reset();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, Clone, PartialEq, Eq)]
    enum TestAction {
        AlwaysSuccess,
        AlwaysFailure,
        AlwaysRunning,
        CountUp,
    }

    /// Dispatcher body factored as a free fn — callers pass it via a thin closure.
    fn run_test_action(action: &TestAction, bb: &mut Blackboard) -> BtStatus {
        match action {
            TestAction::AlwaysSuccess => {
                bb.set("last", BbValue::Str("success".into()));
                BtStatus::Success
            }
            TestAction::AlwaysFailure => BtStatus::Failure,
            TestAction::AlwaysRunning => BtStatus::Running,
            TestAction::CountUp => {
                let n = match bb.get("count") {
                    Some(BbValue::Int(n)) => *n,
                    _ => 0,
                };
                bb.set("count", BbValue::Int(n + 1));
                if n + 1 >= 3 {
                    BtStatus::Success
                } else {
                    BtStatus::Running
                }
            }
        }
    }

    fn is_ready(bb: &Blackboard) -> bool {
        bb.get_bool("ready")
    }

    #[test]
    fn action_success() {
        let mut node: BtNode<TestAction> = BtNode::action(TestAction::AlwaysSuccess);
        let mut bb = Blackboard::new();
        let mut dispatch = |a: &TestAction, bb: &mut Blackboard| run_test_action(a, bb);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Success);
    }

    #[test]
    fn action_failure() {
        let mut node: BtNode<TestAction> = BtNode::action(TestAction::AlwaysFailure);
        let mut bb = Blackboard::new();
        let mut dispatch = |a: &TestAction, bb: &mut Blackboard| run_test_action(a, bb);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Failure);
    }

    #[test]
    fn condition_true() {
        let mut node: BtNode<TestAction> = BtNode::condition("ready", is_ready);
        let mut bb = Blackboard::new();
        bb.set("ready", BbValue::Bool(true));
        let mut dispatch = |a: &TestAction, bb: &mut Blackboard| run_test_action(a, bb);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Success);
    }

    #[test]
    fn condition_false() {
        let mut node: BtNode<TestAction> = BtNode::condition("ready", is_ready);
        let mut bb = Blackboard::new();
        let mut dispatch = |a: &TestAction, bb: &mut Blackboard| run_test_action(a, bb);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Failure);
    }

    #[test]
    fn sequence_runs_children_in_order() {
        let mut node: BtNode<TestAction> = BtNode::sequence(vec![
            BtNode::action(TestAction::AlwaysSuccess),
            BtNode::action(TestAction::AlwaysSuccess),
            BtNode::action(TestAction::AlwaysSuccess),
        ]);
        let mut bb = Blackboard::new();
        let mut dispatch = |a: &TestAction, bb: &mut Blackboard| run_test_action(a, bb);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Running);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Running);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Success);
    }

    #[test]
    fn sequence_fails_on_first_failure_and_resets() {
        let mut node: BtNode<TestAction> = BtNode::sequence(vec![
            BtNode::action(TestAction::AlwaysSuccess),
            BtNode::action(TestAction::AlwaysFailure),
            BtNode::action(TestAction::AlwaysSuccess),
        ]);
        let mut bb = Blackboard::new();
        let mut dispatch = |a: &TestAction, bb: &mut Blackboard| run_test_action(a, bb);
        node.tick(&mut bb, &mut dispatch); // a ok → running
        let s = node.tick(&mut bb, &mut dispatch); // b fail → Failure + reset
        assert_eq!(s, BtStatus::Failure);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Running); // back to a
    }

    #[test]
    fn sequence_resumes_from_index() {
        let mut node: BtNode<TestAction> = BtNode::sequence(vec![
            BtNode::action(TestAction::CountUp),
            BtNode::action(TestAction::AlwaysSuccess),
        ]);
        let mut bb = Blackboard::new();
        let mut dispatch = |a: &TestAction, bb: &mut Blackboard| run_test_action(a, bb);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Running);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Running);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Running);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Success);
    }

    #[test]
    fn selector_succeeds_on_first_success() {
        let mut node: BtNode<TestAction> = BtNode::selector(vec![
            BtNode::action(TestAction::AlwaysFailure),
            BtNode::action(TestAction::AlwaysSuccess),
            BtNode::action(TestAction::AlwaysFailure),
        ]);
        let mut bb = Blackboard::new();
        let mut dispatch = |a: &TestAction, bb: &mut Blackboard| run_test_action(a, bb);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Success);
    }

    #[test]
    fn selector_fails_if_all_fail() {
        let mut node: BtNode<TestAction> = BtNode::selector(vec![
            BtNode::action(TestAction::AlwaysFailure),
            BtNode::action(TestAction::AlwaysFailure),
        ]);
        let mut bb = Blackboard::new();
        let mut dispatch = |a: &TestAction, bb: &mut Blackboard| run_test_action(a, bb);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Failure);
    }

    #[test]
    fn selector_running_stops_iteration() {
        let mut node: BtNode<TestAction> = BtNode::selector(vec![
            BtNode::action(TestAction::AlwaysFailure),
            BtNode::action(TestAction::AlwaysRunning),
            BtNode::action(TestAction::AlwaysSuccess),
        ]);
        let mut bb = Blackboard::new();
        let mut dispatch = |a: &TestAction, bb: &mut Blackboard| run_test_action(a, bb);
        assert_eq!(node.tick(&mut bb, &mut dispatch), BtStatus::Running);
    }

    #[test]
    fn current_action_reflects_active_node() {
        let node: BtNode<TestAction> = BtNode::sequence(vec![
            BtNode::action(TestAction::AlwaysSuccess),
            BtNode::action(TestAction::CountUp),
        ]);
        let label = node.current_action().unwrap();
        assert!(label.contains("AlwaysSuccess"), "got {label}");
    }

    #[test]
    fn parameterized_actions_carry_data() {
        #[derive(Debug, Clone, PartialEq, Eq)]
        enum ParamAction {
            Travel { destination: String },
            Buy { commodity: String, qty: u32 },
        }
        let tree: BtNode<ParamAction> = BtNode::sequence(vec![
            BtNode::action(ParamAction::Travel { destination: "earth-station".into() }),
            BtNode::action(ParamAction::Buy { commodity: "ore".into(), qty: 50 }),
        ]);
        // Verify the params round-trip through Clone
        let cloned = tree.clone();
        if let BtNode::Sequence { children, .. } = cloned {
            if let BtNode::Action(ParamAction::Travel { destination }) = &children[0] {
                assert_eq!(destination, "earth-station");
            } else {
                panic!("first action should be Travel");
            }
        } else {
            panic!("root should be Sequence");
        }
    }
}
