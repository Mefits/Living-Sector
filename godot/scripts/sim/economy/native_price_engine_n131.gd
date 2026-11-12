extends RefCounted
## Exact source: native/crates/sim_core/src/economy/price_engine.rs (frozen 6e40615).
## Pure pricing calculation; caller owns market state and transaction ledger.
const ABSOLUTE_PRICE_CEILING := 500.0
const URGENCY_ONSET_TICKS := 20
const URGENCY_RAMP_TICKS := 50
const URGENCY_MAX_MULTIPLIER := 2.5
const MAX_PRICE_CHANGE_PER_TICK := 0.05

static func urgency_multiplier(shortage_ticks: int) -> float:
	if shortage_ticks <= URGENCY_ONSET_TICKS:
		return 1.0
	return minf(1.0 + float(shortage_ticks - URGENCY_ONSET_TICKS) / float(URGENCY_RAMP_TICKS), URGENCY_MAX_MULTIPLIER)

static func coverage_to_pressure(coverage: float) -> float:
	if coverage < 0.5:
		return 1.0
	if coverage < 2.0:
		return 0.6 + (2.0 - coverage) / 4.0 * 0.4
	if coverage < 10.0:
		return (10.0 - coverage) / 20.0
	if coverage < 200.0:
		return 0.0
	if coverage < 1000.0:
		return -0.2
	if coverage < 10000.0:
		return -0.5
	return -1.0

static func recalculate(current_price: float, supply: float, demand: float, elasticity: float, shortage_ticks: int) -> float:
	var coverage := supply / maxf(demand, 1.0)
	var pressure := coverage_to_pressure(coverage)
	var effective_elasticity := elasticity * urgency_multiplier(shortage_ticks) if pressure > 0.0 else elasticity
	var change := clampf(pressure * effective_elasticity, -MAX_PRICE_CHANGE_PER_TICK, MAX_PRICE_CHANGE_PER_TICK)
	var rounded := floorf(current_price * (1.0 + change) * 100.0 + 0.5) / 100.0
	return clampf(rounded, 1.0, ABSOLUTE_PRICE_CEILING)

static func apply_spread(base_price: float, spread: float) -> Dictionary:
	var half := spread / 2.0
	return {
		"buy": floorf(base_price * (1.0 + half) * 100.0 + 0.5) / 100.0,
		"sell": floorf(base_price * (1.0 - half) * 100.0 + 0.5) / 100.0
	}
