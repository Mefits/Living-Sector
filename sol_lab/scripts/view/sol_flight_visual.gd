extends RefCounted
## Single presentation-only flight geometry for Sol colonizer and freighter.
## Arrival/departure timestamps and cargo remain owned by simulation.
## The SystemBalance native orbital intercept predicts a moving target for
## PHYSICAL navigation; this bounded cubic merely draws between the
## already-committed departure and a predicted ARRIVAL screen position.

static func fraction(departure: float, arrival: float, visual_time: float) -> float:
 if arrival <= departure:
  return 1.0
 return clampf((visual_time - departure) / (arrival - departure), 0.0, 1.0)

static func curve(start: Vector2, finish: Vector2) -> PackedVector2Array:
 var chord: Vector2 = finish - start
 var distance: float = chord.length()
 if distance < 0.001:
  return PackedVector2Array([start, start, finish, finish])
 var normal: Vector2 = Vector2(-chord.y, chord.x) / distance
 # Keep the same screen-side bow for the return leg; geometry is not
 # a physical engine impulse and must not change any saved ship state.
 if normal.y > 0.0:
  normal = -normal
 var bow: float = minf(distance * 0.25, 140.0)
 return PackedVector2Array([start,
  start + chord * 0.27 + normal * bow,
  start + chord * 0.73 + normal * bow,
  finish])

static func point(control: PackedVector2Array, value: float) -> Vector2:
 var t: float = clampf(value, 0.0, 1.0)
 var inverse: float = 1.0 - t
 return control[0] * (inverse * inverse * inverse) + (
  control[1] * (3.0 * inverse * inverse * t)) + (
  control[2] * (3.0 * inverse * t * t)) + control[3] * (t * t * t)

static func tangent(control: PackedVector2Array, value: float) -> Vector2:
 var t: float = clampf(value, 0.0, 1.0)
 var inverse: float = 1.0 - t
 var derivative: Vector2 = (control[1] - control[0]) * (
  3.0 * inverse * inverse) + (control[2] - control[1]) * (
  6.0 * inverse * t) + (control[3] - control[2]) * (3.0 * t * t)
 if derivative.length_squared() < 0.000001:
  derivative = control[3] - control[0]
 return derivative.normalized() if derivative.length_squared() > 0.0 else Vector2.RIGHT
