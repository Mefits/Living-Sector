extends RefCounted
## N149 small but source-critical native ShipCargo and ShipFuel methods.
## Frozen Rust agents/ship/components.rs::ShipCargo::{used,free},
## ::ShipFuel::fraction. No fabricated cargo capacity, free fuel, market
## supply or resource mutation. Error on invalid source values.

const MAX_U32: int = 4294967295

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func cargo_used_and_free(cargo: Dictionary, capacity: int) -> Dictionary:
	## Rust ShipCargo::used sums u32 Cargo values, and free performs
	## capacity.saturating_sub(used). A malformed over-u32 sum is
	## rejected rather than wrapping/inventing free cargo room.
	if capacity < 0 or capacity > MAX_U32:
		return _fail("invalid_rust_u32_cargo_capacity")
	var used: int = 0
	for commodity in cargo:
		if not (commodity is String) or typeof(cargo[commodity]) != TYPE_INT:
			return _fail("invalid_native_cargo_entry")
		var qty: int = int(cargo[commodity])
		if qty < 0 or qty > MAX_U32 or used > MAX_U32 - qty:
			return _fail("invalid_rust_u32_cargo_sum")
		used += qty
	return {"ok": true, "used": used, "free": maxi(0, capacity - used),
		"capacity": capacity}

static func fuel_fraction(fuel: float, fuel_capacity: float) -> Dictionary:
	## Rust ShipFuel::fraction: when fuel_capacity > 0.0 divide,
	## otherwise return 0.0. No automatic 0..1 clamp (native doesn't).
	if not is_finite(fuel) or not is_finite(fuel_capacity):
		return _fail("nonfinite_native_fuel")
	var fraction: float = fuel / fuel_capacity if fuel_capacity > 0.0 else 0.0
	if not is_finite(fraction):
		return _fail("nonfinite_native_fuel_fraction")
	return {"ok": true, "fraction": fraction}
