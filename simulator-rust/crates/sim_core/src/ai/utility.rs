use crate::ai::personality::{Axis, Personality};

/// A single consideration: a value 0.0–1.0 paired with the personality axis it targets.
#[derive(Debug, Clone, Copy)]
pub struct Consideration {
    pub value: f32,
    pub axis: Axis,
}

impl Consideration {
    pub fn new(value: f32, axis: Axis) -> Self {
        Self {
            value: value.clamp(0.0, 1.0),
            axis,
        }
    }
}

/// How a consideration affects an action's score.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Direction {
    /// Higher consideration value → more reason to take this action.
    Positive,
    /// Higher consideration value → less reason to take this action.
    Negative,
}

/// An action with its relevant consideration factors.
#[derive(Debug, Clone)]
pub struct ActionSpec {
    pub name: &'static str,
    /// (consideration_name, direction)
    pub factors: Vec<(&'static str, Direction)>,
}

impl ActionSpec {
    pub fn new(name: &'static str, factors: Vec<(&'static str, Direction)>) -> Self {
        Self { name, factors }
    }
}

/// Score a single action against a set of considerations and a personality.
///
/// Score = Σ(consideration_value × personality_weight) for positive factors
///       − Σ(consideration_value × personality_weight) for negative factors
pub fn score_action(
    spec: &ActionSpec,
    considerations: &std::collections::HashMap<&'static str, Consideration>,
    personality: &Personality,
) -> f32 {
    spec.factors
        .iter()
        .filter_map(|(key, direction)| {
            let c = considerations.get(key)?;
            let weight = personality.weight(c.axis);
            let contribution = c.value * weight;
            Some(match direction {
                Direction::Positive => contribution,
                Direction::Negative => -contribution,
            })
        })
        .sum()
}

/// Score all actions, apply archetype bonuses, and return the best one.
///
/// Returns `("idle", 0.0)` if no action scores above zero.
pub fn best_action(
    actions: &[ActionSpec],
    considerations: &std::collections::HashMap<&'static str, Consideration>,
    personality: &Personality,
) -> (&'static str, f32) {
    let mut best_name = "idle";
    let mut best_score = 0.0_f32;

    for spec in actions {
        let base = score_action(spec, considerations, personality);
        let bonus = personality
            .prefer_goals
            .get(spec.name)
            .copied()
            .unwrap_or(0.0);
        let total = base + bonus;
        if total > best_score {
            best_score = total;
            best_name = spec.name;
        }
    }

    (best_name, best_score)
}

/// Return all actions scored and sorted descending — useful for debugging.
pub fn rank_actions(
    actions: &[ActionSpec],
    considerations: &std::collections::HashMap<&'static str, Consideration>,
    personality: &Personality,
) -> Vec<(&'static str, f32)> {
    let mut scored: Vec<_> = actions
        .iter()
        .map(|spec| {
            let base = score_action(spec, considerations, personality);
            let bonus = personality
                .prefer_goals
                .get(spec.name)
                .copied()
                .unwrap_or(0.0);
            (spec.name, base + bonus)
        })
        .collect();
    scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    scored
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn make_considerations(pairs: &[(&'static str, f32, Axis)]) -> HashMap<&'static str, Consideration> {
        pairs
            .iter()
            .map(|(k, v, ax)| (*k, Consideration::new(*v, *ax)))
            .collect()
    }

    #[test]
    fn high_fuel_urgency_picks_refuel_for_safety_personality() {
        let personality = Personality::cautious_trader();

        let considerations = make_considerations(&[
            ("fuel_urgency", 0.9, Axis::Safety),
            ("trade_profit", 0.6, Axis::Profit),
        ]);

        let actions = vec![
            ActionSpec::new("trade_run", vec![("trade_profit", Direction::Positive)]),
            ActionSpec::new("refuel", vec![("fuel_urgency", Direction::Positive)]),
        ];

        let (winner, score) = best_action(&actions, &considerations, &personality);
        // cautious_trader: safety=0.9 → refuel scores 0.9*0.9=0.81
        // trade_run: profit=0.6 → 0.6*0.6=0.36
        assert_eq!(winner, "refuel");
        assert!(score > 0.0);
    }

    #[test]
    fn aggressive_trader_picks_trade_over_safety() {
        let personality = Personality::aggressive_trader();

        let considerations = make_considerations(&[
            ("fuel_urgency", 0.4, Axis::Safety),  // moderate fuel concern
            ("trade_profit", 0.7, Axis::Profit),  // good trade available
        ]);

        let actions = vec![
            ActionSpec::new("trade_run", vec![("trade_profit", Direction::Positive)]),
            ActionSpec::new("refuel", vec![("fuel_urgency", Direction::Positive)]),
        ];

        let (winner, _score) = best_action(&actions, &considerations, &personality);
        // aggressive: profit=0.95 → trade 0.7*0.95=0.665; safety=0.2 → refuel 0.4*0.2=0.08
        assert_eq!(winner, "trade_run");
    }

    #[test]
    fn returns_idle_when_nothing_scores_above_zero() {
        let personality = Personality::balanced_trader();
        let considerations: HashMap<&'static str, Consideration> = HashMap::new();
        let actions = vec![
            ActionSpec::new("trade_run", vec![("trade_profit", Direction::Positive)]),
        ];
        let (winner, score) = best_action(&actions, &considerations, &personality);
        assert_eq!(winner, "idle");
        assert_eq!(score, 0.0);
    }

    #[test]
    fn prefer_goals_bonus_breaks_tie() {
        let mut personality = Personality::balanced_trader();
        personality.prefer_goals.insert("fulfill_contract".into(), 0.5);

        let considerations = make_considerations(&[
            ("contract_available", 0.5, Axis::Loyalty),
            ("trade_profit", 0.5, Axis::Profit),
        ]);

        let actions = vec![
            ActionSpec::new("trade_run", vec![("trade_profit", Direction::Positive)]),
            ActionSpec::new("fulfill_contract", vec![("contract_available", Direction::Positive)]),
        ];

        let (winner, _) = best_action(&actions, &considerations, &personality);
        // Without bonus: both score 0.5*0.5=0.25. With bonus, fulfill_contract gets +0.5.
        assert_eq!(winner, "fulfill_contract");
    }

    #[test]
    fn rank_actions_descending() {
        let personality = Personality::aggressive_trader();
        let considerations = make_considerations(&[
            ("trade_profit", 0.9, Axis::Profit),
            ("fuel_urgency", 0.2, Axis::Safety),
        ]);
        let actions = vec![
            ActionSpec::new("trade_run", vec![("trade_profit", Direction::Positive)]),
            ActionSpec::new("refuel", vec![("fuel_urgency", Direction::Positive)]),
        ];
        let ranked = rank_actions(&actions, &considerations, &personality);
        assert_eq!(ranked[0].0, "trade_run");
        assert!(ranked[0].1 > ranked[1].1);
    }
}
