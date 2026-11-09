//! Portable, deterministic strategic valuation kernel.
 //! No ECS, market, planning-framework or benchmark dependencies.
 //! The game currently uses this in read-only shadow mode; it does not authorize spending.
 
 #[derive(Clone, Copy, Debug)]
 pub struct Candidate {
     /// Already net of purchased inputs, labor and planned payments; credits-equivalent.
     pub estimated_net_value: f64,
     pub ready: bool,
     pub projected_coverage: f64,
     pub delay_ticks: u64,
     pub horizon_ticks: u64,
     pub treasury_after_commitment: i64,
     pub minimum_treasury_reserve: i64,
     /// Actual shortage time in base simulation ticks, not number of actions.
     pub shortage_ticks: u32,
     /// 2 for survival goods, 1 for critical logistics, 0 for other industry.
     pub criticality: u8,
 }
 
 #[derive(Clone, Copy, Debug, PartialEq)]
 pub struct Assessment {
     pub strategic_value: f64,
     pub urgency_multiplier: f64,
 }
 
 /// Compare projected economic OUTCOMES, not counts of actions or proxy score production.
 /// A reserve breach, an invalid project or an exhausted horizon is not a proposal.
 /// The long-term capability value (science, T2+, diplomacy) must later be provided as
 /// genuine forecasts once those systems exist in native Genesis.
 pub fn evaluate(c: Candidate) -> Option<Assessment> {
     if !c.ready
         || !c.estimated_net_value.is_finite()
         || c.estimated_net_value <= 0.0
         || !c.projected_coverage.is_finite()
         || c.projected_coverage <= 0.0
         || c.delay_ticks >= c.horizon_ticks
         || c.treasury_after_commitment < c.minimum_treasury_reserve
     {
         return None;
     }
     let urgency = (f64::from(c.shortage_ticks) / c.horizon_ticks as f64)
         .clamp(0.0, 1.0);
     let criticality = f64::from(c.criticality.min(2));
     // Small bounded urgency preference. It cannot override negative net value.
     let multiplier = 1.0 + 0.18 * urgency + 0.16 * criticality;
     // The source estimate already discounts delayed production: do not double-discount.
     let score = c.estimated_net_value * multiplier;
     (score.is_finite() && score > 0.0).then_some(Assessment {
         strategic_value: score,
         urgency_multiplier: multiplier,
     })
 }
 
 #[cfg(test)]
 mod tests {
     use super::*;
 
     fn baseline() -> Candidate {
         Candidate {
             estimated_net_value: 100.0,
             ready: true,
             projected_coverage: 10.0,
             delay_ticks: 40,
             horizon_ticks: 1200,
             treasury_after_commitment: 10_000,
             minimum_treasury_reserve: 5_000,
             shortage_ticks: 0,
             criticality: 0,
         }
     }
 
     #[test]
     fn repeated_no_effect_action_cannot_be_a_project() {
         let mut a = baseline();
         a.projected_coverage = 0.0;
         assert!(evaluate(a).is_none());
     }
 
     #[test]
     fn negative_value_and_credit_floor_are_respected() {
         let mut a = baseline();
         a.estimated_net_value = -1.0;
         assert!(evaluate(a).is_none());
         a.estimated_net_value = 100.0;
         a.treasury_after_commitment = 4_999;
         assert!(evaluate(a).is_none());
     }
 
     #[test]
     fn survival_priority_is_bounded_and_traceable() {
         let normal = evaluate(baseline()).unwrap();
         let mut urgent = baseline();
         urgent.criticality = 2;
         urgent.shortage_ticks = 1_200;
         let rated = evaluate(urgent).unwrap();
         assert!(rated.strategic_value > normal.strategic_value);
         assert!(rated.urgency_multiplier <= 1.5);
     }
 
     #[test]
     fn later_than_horizon_cannot_promise_benefit() {
         let mut a = baseline();
         a.delay_ticks = a.horizon_ticks;
         assert!(evaluate(a).is_none());
     }
 }
 