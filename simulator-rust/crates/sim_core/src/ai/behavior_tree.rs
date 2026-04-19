/// Behavior tree engine for tactical agent execution.
///
/// Once the utility layer selects a goal (e.g., `trade_run`), a behavior tree
/// handles step-by-step execution. The tree resumes where it left off across
/// ticks via the `Sequence` node's saved index.
///
/// Node types:
/// - `Sequence`  — run children in order; fail on first failure; resume on `Running`
/// - `Selector`  — try children in order; succeed on first success; always restart
/// - `Condition` — evaluate a predicate; returns Success or Failure
/// - `Action`    — execute a side-effecting step; returns Success, Failure, or Running
///
/// The `Blackboard` is a `HashMap<&'static str, BbValue>` for scratch data that
/// lives only for the current BT run. The agent's persistent state is passed via
/// the `context` field on the blackboard (filled in by the agent layer, Phase 4).

use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq)]
pub enum BtStatus {
    Running,
    Success,
    Failure,
}

/// Scratch value types for the blackboard.
#[derive(Debug, Clone)]
pub enum BbValue {
    Int(i64),
    Float(f32),
    Bool(bool),
    Str(String),
}

/// Per-tick scratch data carried through the tree. The agent attaches its own
/// state pointer before calling `tick()`. For Phase 1 testing, this is
/// self-contained; Phase 4 will add a `ship: &mut ShipState` reference.
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

pub type ActionFn = fn(&mut Blackboard) -> BtStatus;
pub type ConditionFn = fn(&Blackboard) -> bool;

/// A behavior tree node. Clone is derived so agent state can store the tree
/// without needing Arc/Box. Function pointers are `fn` (not closures) so they
/// are trivially Copy+Clone.
#[derive(Clone)]
pub enum BtNode {
    /// Run children in order. Remember position across ticks.
    Sequence {
        children: Vec<BtNode>,
        /// Index of the child currently executing. Resets to 0 on success or failure.
        index: usize,
    },
    /// Try children in order; succeed on first success. Always resets to 0.
    Selector { children: Vec<BtNode> },
    /// Evaluate a predicate. Returns Success or Failure instantly.
    Condition {
        name: &'static str,
        check: ConditionFn,
    },
    /// Execute one step. May return Running to be called again next tick.
    Action {
        name: &'static str,
        run: ActionFn,
    },
}

impl std::fmt::Debug for BtNode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BtNode::Sequence { children, index } => {
                write!(f, "Sequence(idx={}, {} children)", index, children.len())
            }
            BtNode::Selector { children } => {
                write!(f, "Selector({} children)", children.len())
            }
            BtNode::Condition { name, .. } => write!(f, "Condition({name})"),
            BtNode::Action { name, .. } => write!(f, "Action({name})"),
        }
    }
}

impl BtNode {
    // --- Constructors ---

    pub fn sequence(children: Vec<BtNode>) -> Self {
        BtNode::Sequence { children, index: 0 }
    }

    pub fn selector(children: Vec<BtNode>) -> Self {
        BtNode::Selector { children }
    }

    pub fn condition(name: &'static str, check: ConditionFn) -> Self {
        BtNode::Condition { name, check }
    }

    pub fn action(name: &'static str, run: ActionFn) -> Self {
        BtNode::Action { name, run }
    }

    // --- Tick ---

    /// Advance the tree by one step. Mutates `self` to save resume state
    /// (sequence index). Mutates `bb` for side effects. Returns the status.
    pub fn tick(&mut self, bb: &mut Blackboard) -> BtStatus {
        match self {
            BtNode::Action { run, .. } => run(bb),

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
                let status = children[*index].tick(bb);
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
                    match child.tick(bb) {
                        BtStatus::Success => return BtStatus::Success,
                        BtStatus::Running => return BtStatus::Running,
                        BtStatus::Failure => continue,
                    }
                }
                BtStatus::Failure
            }
        }
    }

    /// Returns the name of the currently active leaf node, for display.
    pub fn current_action(&self) -> Option<&'static str> {
        match self {
            BtNode::Action { name, .. } => Some(name),
            BtNode::Condition { name, .. } => Some(name),
            BtNode::Sequence { children, index } => {
                children.get(*index).and_then(|c| c.current_action())
            }
            BtNode::Selector { children } => {
                children.first().and_then(|c| c.current_action())
            }
        }
    }

    /// Reset sequence index to 0. Call when switching goals.
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

    fn always_success(bb: &mut Blackboard) -> BtStatus {
        bb.set("last", BbValue::Str("success".into()));
        BtStatus::Success
    }

    fn always_failure(_bb: &mut Blackboard) -> BtStatus {
        BtStatus::Failure
    }

    fn always_running(_bb: &mut Blackboard) -> BtStatus {
        BtStatus::Running
    }

    fn count_up(bb: &mut Blackboard) -> BtStatus {
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

    fn is_ready(bb: &Blackboard) -> bool {
        bb.get_bool("ready")
    }

    #[test]
    fn action_success() {
        let mut node = BtNode::action("ok", always_success);
        let mut bb = Blackboard::new();
        assert_eq!(node.tick(&mut bb), BtStatus::Success);
    }

    #[test]
    fn action_failure() {
        let mut node = BtNode::action("fail", always_failure);
        let mut bb = Blackboard::new();
        assert_eq!(node.tick(&mut bb), BtStatus::Failure);
    }

    #[test]
    fn condition_true() {
        let mut node = BtNode::condition("ready", is_ready);
        let mut bb = Blackboard::new();
        bb.set("ready", BbValue::Bool(true));
        assert_eq!(node.tick(&mut bb), BtStatus::Success);
    }

    #[test]
    fn condition_false() {
        let mut node = BtNode::condition("ready", is_ready);
        let mut bb = Blackboard::new();
        assert_eq!(node.tick(&mut bb), BtStatus::Failure);
    }

    #[test]
    fn sequence_runs_children_in_order() {
        // sequence of 3 always-success → returns Running twice then Success
        let mut node = BtNode::sequence(vec![
            BtNode::action("a", always_success),
            BtNode::action("b", always_success),
            BtNode::action("c", always_success),
        ]);
        let mut bb = Blackboard::new();

        assert_eq!(node.tick(&mut bb), BtStatus::Running); // a done, b next
        assert_eq!(node.tick(&mut bb), BtStatus::Running); // b done, c next
        assert_eq!(node.tick(&mut bb), BtStatus::Success); // c done, all done
    }

    #[test]
    fn sequence_fails_on_first_failure_and_resets() {
        let mut node = BtNode::sequence(vec![
            BtNode::action("a", always_success),
            BtNode::action("b", always_failure),
            BtNode::action("c", always_success),
        ]);
        let mut bb = Blackboard::new();

        node.tick(&mut bb); // a: success → running
        let status = node.tick(&mut bb); // b: failure → fail + reset
        assert_eq!(status, BtStatus::Failure);

        // After reset, should start from a again
        assert_eq!(node.tick(&mut bb), BtStatus::Running); // back to a
    }

    #[test]
    fn sequence_resumes_from_index() {
        // count_up needs 3 ticks to succeed
        let mut node = BtNode::sequence(vec![
            BtNode::action("count", count_up),
            BtNode::action("done", always_success),
        ]);
        let mut bb = Blackboard::new();

        // count_up ticks 1, 2: Running
        assert_eq!(node.tick(&mut bb), BtStatus::Running);
        assert_eq!(node.tick(&mut bb), BtStatus::Running);
        // count_up tick 3: Success → moves to "done" → Running (done is next tick)
        assert_eq!(node.tick(&mut bb), BtStatus::Running);
        // "done" succeeds → whole sequence succeeds
        assert_eq!(node.tick(&mut bb), BtStatus::Success);
    }

    #[test]
    fn selector_succeeds_on_first_success() {
        let mut node = BtNode::selector(vec![
            BtNode::action("fail1", always_failure),
            BtNode::action("ok", always_success),
            BtNode::action("never", always_failure),
        ]);
        let mut bb = Blackboard::new();
        assert_eq!(node.tick(&mut bb), BtStatus::Success);
    }

    #[test]
    fn selector_fails_if_all_fail() {
        let mut node = BtNode::selector(vec![
            BtNode::action("f1", always_failure),
            BtNode::action("f2", always_failure),
        ]);
        let mut bb = Blackboard::new();
        assert_eq!(node.tick(&mut bb), BtStatus::Failure);
    }

    #[test]
    fn selector_running_stops_iteration() {
        let mut node = BtNode::selector(vec![
            BtNode::action("fail", always_failure),
            BtNode::action("run", always_running),
            BtNode::action("never", always_success),
        ]);
        let mut bb = Blackboard::new();
        assert_eq!(node.tick(&mut bb), BtStatus::Running);
    }

    #[test]
    fn current_action_reflects_active_node() {
        let node = BtNode::sequence(vec![
            BtNode::action("step_a", always_success),
            BtNode::action("step_b", always_success),
        ]);
        assert_eq!(node.current_action(), Some("step_a"));
    }
}
