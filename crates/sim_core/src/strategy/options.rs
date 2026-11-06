//! Compare ways to address one commodity shortage on a common horizon.
use super::*;
use crate::agents::{facility, market};
use crate::economy::recipes;

const HORIZON: u64 = 1_200;
/// Approximation in base ticks for finding a carrier, purchase and flight.
const SHIPMENT_TIME: u64 = 2 * faction::SUBSIDY_CHECK_INTERVAL_BASE;
const DELIVERY_REWARD: i64 = faction::SUBSIDY_BASE_PAYMENT * 2;

#[derive(Clone, Debug, Serialize)]
pub struct Alternative {
    pub action: &'static str,
    pub source: Option<String>,
    pub status: &'static str,
    pub reason: String,
    pub first_payment: i64,
    pub total_commitment: i64,
    pub treasury_after: i64,
    pub estimated_delay_ticks: u64,
    pub shipment_count: u32,
    pub material: Option<Commodity>,
    pub site_id: Option<String>,
    pub source_stock: Option<f64>,
    pub first_purchase_cost: Option<i64>,
    pub covered_units: f64,
    pub estimated_net_value: Option<f64>,
}

pub(super) fn same_problem(a: &Goal, b: &Goal) -> bool {
    a.commodity == b.commodity && a.destination == b.destination
}

fn finite_stock(stock: Option<&f32>) -> f64 {
    stock.copied().filter(|v| v.is_finite() && *v > 0.0).map_or(0.0, f64::from)
}

struct Need<'a> {
    market: Option<&'a MarketPricing>,
    commodity: Commodity,
    demand: f64,
    stock: f64,
    unit_value: f64,
}

impl<'a> Need<'a> {
    fn new(sources: &'a sourcing::Sources<'_>, goal: &Goal) -> Self {
        let market = sources.market(&goal.destination);
        let commodity = goal.commodity;
        Self {
            market, commodity,
            demand: market.map_or(0.0, |m| finite_stock(m.demand.get(&commodity))),
            stock: market.map_or(0.0, |m| finite_stock(m.supply.get(&commodity))),
            unit_value: market.map_or(f64::from(commodity.base_price()), |m| {
                let price = m.price(commodity);
                if price.is_finite() && price > 0.0 { f64::from(price) }
                else { f64::from(commodity.base_price()) }
            }),
        }
    }

    fn unmet_at_horizon(&self) -> f64 {
        (self.demand * HORIZON as f64 / market::DEMAND_WINDOW_BASE as f64 - self.stock).max(0.0)
    }

    fn production(&self, offer: &construction::Offer, delay: u64) -> (f64, f64) {
        let productive_ticks = HORIZON.saturating_sub(delay);
        if offer.facility_type.as_deref() == Some("mining_rig") {
            let cycles = productive_ticks / facility::MINING_INTERVAL_BASE;
            return (cycles as f64 * f64::from(facility::MINING_YIELD_PER_CYCLE)
                * f64::from(offer.raw_richness), 0.0);
        }
        let (Some(kind), Some(market)) = (&offer.facility_type, self.market) else {
            return (0.0, 0.0);
        };
        let batches = (productive_ticks / facility::RECIPE_INTERVAL_BASE) as u32;
        // One batch per cycle and inputs already at the destination. Do not
        // assume future replenishment or that several recipes share the stock.
        recipes::for_facility_type(kind)
            .filter(|recipe| recipe.outputs.iter().any(|&(c, _)| c == self.commodity))
            .map(|recipe| {
                let mut supply = market.supply.clone();
                let output_per_batch = recipe.outputs.iter()
                    .filter(|&&(commodity, _)| commodity == self.commodity)
                    .map(|&(_, amount)| f64::from(amount)).sum::<f64>();
                let useful_batches = (self.unmet_at_horizon() / output_per_batch).ceil() as u32;
                let output = recipes::execute(
                    recipe, &mut supply, 1.0, batches.min(useful_batches), Some(&market.prices),
                );
                let units = finite_stock(output.get(&self.commodity));
                let input_cost: f64 = recipe.inputs.iter().map(|&(c, _)| {
                    let consumed = finite_stock(market.supply.get(&c)) - finite_stock(supply.get(&c));
                    consumed.max(0.0) * f64::from(market.price(c))
                }).sum();
                (units, input_cost)
            })
            .filter(|(_, cost)| cost.is_finite() && *cost >= 0.0)
            .max_by(|(a, ac), (b, bc)| {
                (a.min(self.unmet_at_horizon()) * self.unit_value - ac)
                    .total_cmp(&(b.min(self.unmet_at_horizon()) * self.unit_value - bc))
            })
            .unwrap_or((0.0, 0.0))
    }
}

impl Alternative {
    fn wait(treasury: i64) -> Self {
        Self {
            action: "wait", source: None, status: "ready", reason: "reconsider_next_cycle".into(),
            first_payment: 0, total_commitment: 0, treasury_after: treasury,
            estimated_delay_ticks: 0, shipment_count: 0, material: None, site_id: None,
            source_stock: None, first_purchase_cost: None, covered_units: 0.0,
            estimated_net_value: Some(0.0),
        }
    }

    fn assess(&mut self, reason: &str, units: f64, delay: u64, other_cost: f64, need: &Need<'_>) {
        self.reason = reason.into();
        self.covered_units = units.min(need.unmet_at_horizon());
        if reason != "ready" {
            self.status = "blocked";
            self.estimated_net_value = None;
            return;
        }
        let timing = HORIZON.saturating_sub(delay) as f64 / HORIZON as f64;
        let net = self.covered_units * need.unit_value * timing
            - self.total_commitment as f64 - other_cost;
        self.estimated_net_value = Some(net);
        self.reason = if self.covered_units == 0.0 { "no_projected_shortage_relief" }
            else if net <= 0.0 { "cost_exceeds_projected_relief" }
            else { "positive_projected_relief" }.into();
    }
}

/// Each administrator can be busy with an existing contract. That status
/// blocks another assignment even if a different shortage has stock.
fn alternatives(
    view: &FactionView, sources: &sourcing::Sources<'_>, goal: &Goal, mult: u32,
) -> Vec<Alternative> {
    let need = Need::new(sources, goal);
    let mult = u64::from(mult.max(1));
    let mut delivery = Alternative {
        action: "deliver", first_payment: DELIVERY_REWARD, total_commitment: DELIVERY_REWARD,
        treasury_after: view.treasury.saturating_sub(DELIVERY_REWARD),
        estimated_delay_ticks: SHIPMENT_TIME * mult, shipment_count: 1,
        material: Some(goal.commodity), ..Alternative::wait(view.treasury)
    };
    let assessment = view.assessments.iter().find(|a| same_problem(&a.goal, goal));
    delivery.source = assessment.and_then(|a| a.source.clone());
    if let Some(source) = &delivery.source {
        delivery.source_stock = sources.market(source).map(|m| finite_stock(m.supply.get(&goal.commodity)));
        delivery.first_purchase_cost = sources.quote(&view.faction_id, source, goal.commodity, faction::SUBSIDY_QUANTITY);
    }
    let delivery_reason = if view.reason == "existing_contract" { "administrator_busy" }
        else { assessment.map_or("no_current_shortage", |a| a.reason.as_str()) };
    delivery.assess(delivery_reason, f64::from(faction::SUBSIDY_QUANTITY), SHIPMENT_TIME, 0.0, &need);

    let mut build = Alternative {
        action: "build", ..Alternative::wait(view.treasury)
    };
    let construction = view.construction.as_ref();
    let offer = construction.and_then(|c| c.offers.iter().find(|offer| same_problem(&offer.goal, goal)));
    if let Some(offer) = offer {
        let delay = u64::from(offer.shipments()) * SHIPMENT_TIME;
        build.first_payment = faction::CONSTRUCTION_BASE_PAYMENT;
        build.total_commitment = offer.total_cost();
        build.treasury_after = view.treasury.saturating_sub(build.total_commitment);
        build.estimated_delay_ticks = delay * mult;
        build.shipment_count = offer.shipments();
        build.material = Some(offer.material);
        build.source = offer.source.clone();
        build.site_id = offer.site_id.clone();
        if let Some(source) = &build.source {
            build.source_stock = sources.market(source).map(|m| finite_stock(m.supply.get(&offer.material)));
            build.first_purchase_cost = sources.quote(&view.faction_id, source, offer.material,
                offer.remaining.min(faction::CONSTRUCTION_QUANTITY));
        }
        let (units, input_cost) = need.production(offer, delay);
        // Only the next lot is required to fund the next contract. Discount
        // the output forecast when the source cannot cover all remaining lots.
        let coverage = if offer.remaining == 0 { 0.0 } else {
            (build.source_stock.unwrap_or(0.0) / f64::from(offer.remaining)).min(1.0)
        };
        build.assess(offer.reason, units * coverage, delay, input_cost * coverage, &need);
    } else {
        let reason = if construction.is_some_and(|c| c.reason == "existing_contract") {
            "administrator_busy"
        } else {
            "no_construction_proposal"
        };
        build.assess(reason, 0.0, 0, 0.0, &need);
    }
    vec![delivery, build, Alternative::wait(view.treasury)]
}

pub(super) struct Comparison {
    pub goal: Goal,
    pub alternatives: Vec<Alternative>,
    pub selected: &'static str,
}

pub(super) fn compare(view: &FactionView, sources: &sourcing::Sources<'_>, mult: u32) -> Option<Comparison> {
    let mut goals = view.goals.clone();
    if let Some(construction) = &view.construction {
        for offer in &construction.offers {
            if !goals.iter().any(|goal| same_problem(goal, &offer.goal)) {
                goals.push(offer.goal.clone());
            }
        }
    }
    goals.sort_by(|a,b| b.score.total_cmp(&a.score)
        .then_with(|| a.destination.cmp(&b.destination))
        .then_with(|| a.commodity.as_str().cmp(b.commodity.as_str())));
    let mut waiting = None;
    for goal in goals {
        let alternatives = alternatives(view, sources, &goal, mult);
        let selected = alternatives.iter()
            .filter(|a| a.estimated_net_value.is_some_and(|v| v > 0.0))
            .max_by(|a,b| a.estimated_net_value.unwrap().total_cmp(&b.estimated_net_value.unwrap())
                .then_with(|| b.estimated_delay_ticks.cmp(&a.estimated_delay_ticks))
                .then_with(|| b.action.cmp(a.action)))
            .map_or("wait", |a| a.action);
        let comparison = Comparison { goal, alternatives, selected };
        if selected != "wait" { return Some(comparison); }
        waiting.get_or_insert(comparison);
    }
    waiting
}

pub(super) fn horizon_ticks(mult: u32) -> u64 {
    HORIZON * u64::from(mult.max(1))
}
