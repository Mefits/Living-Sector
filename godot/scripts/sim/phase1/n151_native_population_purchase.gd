extends RefCounted
## N151 — frozen sim_core/agents/population.rs::purchase_consumption.
## Pure single-transaction admission; only real World ECS apply may debit.
## The source permits fractional Food/Water and transfers full credits
## to FacilityOperations, never to an imaginary market-bank account.
const MAX_I64: int = 9223372036854775807
const MIN_I64: int = -9223372036854775807 - 1

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _f32(value: float) -> float:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, value)
	return float(bytes.decode_float(0))

static func _f32_step_down_positive(value: float) -> float:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, value)
	var bits: int = int(bytes.decode_u32(0))
	bytes.encode_u32(0, maxi(0, bits - 1))
	return float(bytes.decode_float(0))

static func prepare_purchase(pop: Dictionary, market: Dictionary,
		seller: Dictionary, commodity: String, needed: float, tick: int,
		original_base_prices: Dictionary) -> Dictionary:
	## Keys are real native ECS projections. Seller is the real owning
	## FacilityOperations of MarketIdentity.facility, NEVER an invented bank.
	for k in ["id", "facility_location", "total_wealth"]:
		if not pop.has(k):
			return _fail("missing_population" if k=="id" else "missing_wallet")
	for k in ["id", "facility_location", "owner_facility_id", "supply", "prices"]:
		if not market.has(k):
			return _fail("missing_market")
	for k in ["id", "credits"]:
		if not seller.has(k):
			return _fail("missing_seller_economy")
	if not (pop["id"] is String and pop["facility_location"] is String and
			market["id"] is String and market["facility_location"] is String and
			market["owner_facility_id"] is String and seller["id"] is String):
		return _fail("invalid_native_identity")
	if str(pop["facility_location"]) != str(market["facility_location"]):
		return _fail("wrong_location")
	if str(market["owner_facility_id"]) != str(seller["id"]):
		return _fail("missing_seller_economy")
	if not (market["supply"] is Dictionary and market["prices"] is Dictionary):
		return _fail("missing_pricing")
	if typeof(pop["total_wealth"]) != TYPE_INT or typeof(seller["credits"]) != TYPE_INT:
		return _fail("missing_wallet_or_seller_economy")
	if tick < 0 or commodity.is_empty():
		return _fail("invalid_quote")
	var price_v = market["prices"].get(commodity, original_base_prices.get(commodity))
	var stock_v = market["supply"].get(commodity, 0.0)
	if not (typeof(price_v) in [TYPE_FLOAT,TYPE_INT] and
			typeof(stock_v) in [TYPE_FLOAT,TYPE_INT]):
		return _fail("invalid_quote")
	var price: float = float(price_v)
	var stock: float = float(stock_v)
	var cash: int = int(pop["total_wealth"])
	if not (is_finite(needed) and needed > 0.0 and
			is_finite(price) and price > 0.0 and
			is_finite(stock) and stock >= 0.0):
		return _fail("invalid_quote")
	if stock == 0.0:
		return _fail("insufficient_stock")
	if cash <= 0:
		return _fail("insufficient_household_credits")
	# Rust computes min in f64 THEN converts to f32; it may round
	# affordable stock upward by 1 ULP. Step down only in that case.
	var quantity: float = _f32(minf(minf(needed,stock),float(cash)/price))
	if quantity <= 0.0:
		return _fail("insufficient_household_credits")
	var raw_payment: float = ceil(quantity*price)
	if raw_payment > float(cash):
		quantity = _f32_step_down_positive(quantity)
		if quantity <= 0.0:
			return _fail("insufficient_household_credits")
		raw_payment = ceil(quantity*price)
	if not is_finite(raw_payment) or raw_payment >= float(MAX_I64) or raw_payment > float(cash):
		return _fail("invalid_payment")
	var payment: int = int(raw_payment)
	var old_seller: int = int(seller["credits"])
	if payment > 0 and old_seller > MAX_I64 - payment:
		return _fail("credit_overflow")
	var new_seller: int = old_seller+payment
	var result_stock: float = _f32(stock-quantity)
	return {"ok": true, "reason": "", "tick":tick,
		"population_id":pop["id"], "market_id":market["id"],
		"facility_id":seller["id"], "commodity":commodity,
		"needed":needed,"quantity":quantity,"payment":payment,
		"complete":quantity >= needed,
		"preconditions":{"population_wealth":cash,"seller_credits":old_seller,
			"market_supply":stock,"market_posted_price":price},
		"effects":{"population_wealth_delta":-payment,
			"facility_credits_delta":payment,"market_supply_delta":-quantity,
			"record_consumption":{"commodity":commodity,"quantity":quantity,"tick":tick},
			"population_sentiment_dirty":true,"facility_operations_dirty":true,
			"market_history_dirty":true},
		"after":{"population_wealth":cash-payment,
			"facility_credits":new_seller,"market_supply":result_stock},
		"requires":"single_native_ECS_wallet_seller_market_flow_history_commit"}

static func reserve_population_payment(pop: Dictionary, payment: int) -> Dictionary:
	## Original funding source Population: ONLY escrow reserve for a
	## truly posted delivery contract. Never pay twice at final delivery.
	if not (pop.get("id") is String) or typeof(pop.get("total_wealth"))!=TYPE_INT:
		return _fail("missing_population_or_wallet")
	var cash: int = int(pop["total_wealth"])
	if payment < 0 or cash < payment:
		return _fail("insufficient_population_contract_funding")
	return {"ok":true,"requestor_id":pop["id"],"payment":payment,
		"wealth_before":cash,"wealth_after":cash-payment,
		"funding_source":"population",
		"requires":"native_contractboard_post_and_register_prepaid_same_commit"}
