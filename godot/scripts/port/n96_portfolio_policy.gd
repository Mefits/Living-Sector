extends RefCounted
## N96 — exact native strategy/portfolio_policy.rs valuation kernel.
## Read-only shadow assessment. No authorization to spend or produce.
## Inputs: {estimated_net_value, ready, projected_coverage, delay_ticks,
## horizon_ticks, treasury_after_commitment, minimum_treasury_reserve,
## shortage_ticks, criticality}. Returns empty dictionary for rejected candidate.

static func evaluate(candidate: Dictionary) -> Dictionary:
	var required: Array = ["estimated_net_value", "ready", "projected_coverage", "delay_ticks", "horizon_ticks", "treasury_after_commitment", "minimum_treasury_reserve", "shortage_ticks", "criticality"]
	for key in required:
		if not candidate.has(key):
			return {}
	var value: float = float(candidate.estimated_net_value)
	var coverage: float = float(candidate.projected_coverage)
	var delay: int = int(candidate.delay_ticks)
	var horizon: int = int(candidate.horizon_ticks)
	var treasury: int = int(candidate.treasury_after_commitment)
	var reserve: int = int(candidate.minimum_treasury_reserve)
	var shortage: int = int(candidate.shortage_ticks)
	var criticality: int = int(candidate.criticality)
	if not bool(candidate.ready) or not is_finite(value) or value <= 0.0:
		return {}
	if not is_finite(coverage) or coverage <= 0.0 or horizon <= 0 or delay < 0 or delay >= horizon or treasury < reserve or shortage < 0 or criticality < 0:
		return {}
	var urgency: float = clampf(float(shortage) / float(horizon), 0.0, 1.0)
	var multiplier: float = 1.0 + 0.18 * urgency + 0.16 * float(mini(criticality, 2))
	var score: float = value * multiplier
	if not is_finite(score) or score <= 0.0:
		return {}
	return {"strategic_value": score, "urgency_multiplier": multiplier}

## Stable rank for callers; Rust evaluate() itself only scores a candidate.
## Rejects invalid candidates, preserving their caller-supplied IDs.
static func ranked(candidates: Array) -> Array:
	var results: Array = []
	for c in candidates:
		var a: Dictionary = evaluate(c)
		if not a.is_empty():
			results.append({"id": str(c.get("id", "")), "assessment": a})
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var av: float = float(a.assessment.strategic_value)
		var bv: float = float(b.assessment.strategic_value)
		return av > bv if av != bv else str(a.id) < str(b.id)
	)
	return results
