extends RefCounted
## Ground geometry shared by the district renderer and its freight simulation.
const PORT := Rect2(548, 382, 354, 203)
const PAD := Vector2(676, 449)
const GATE := PAD + Vector2(-8, 89)
const PLOTS = {
 "earth-ac-01": Rect2(419, 282, 108, 79),
 "earth-farm-01": Rect2(54, 400, 176, 104),
 "earth-farm-02": Rect2(244, 400, 162, 104),
 "earth-farm-03": Rect2(54, 522, 176, 96),
 "earth-mine-01": Rect2(56, 82, 116, 92),
 "earth-mine-02": Rect2(195, 82, 116, 92),
 "earth-mine-03": Rect2(56, 195, 116, 92),
 "earth-mine-04": Rect2(195, 195, 116, 92),
 "earth-industry-01": Rect2(393, 82, 148, 99),
 "earth-industry-02": Rect2(560, 82, 138, 99),
 "earth-industry-03": Rect2(714, 82, 147, 99),
 "earth-industry-04": Rect2(573, 198, 134, 79),
 "earth-port-01": Rect2(548, 382, 354, 203),
 "earth-common-01": Rect2(244, 522, 162, 96),
 "earth-common-02": Rect2(726, 198, 135, 79),
 "earth-expansion-01": Rect2(56, 661, 116, 92),
 "earth-expansion-02": Rect2(195, 661, 116, 92),
 "earth-expansion-03": Rect2(334, 661, 116, 92),
 "earth-expansion-04": Rect2(561, 661, 116, 92),
 "earth-common-03": Rect2(429, 400, 105, 104),
}
const CROSS := 371.0
const CONNECTOR := 538.0
const PORT_LANE := 509.0

static func driveway(plot: Rect2) -> PackedVector2Array:
 var center := plot.get_center()
 if plot == PORT:
  return PackedVector2Array([Vector2(PORT.position.x, PORT_LANE),
   Vector2(CONNECTOR, PORT_LANE)])
 if plot.position.y >= 661 and plot.position.y < 791:
  return PackedVector2Array([Vector2(center.x, plot.position.y), Vector2(center.x, 640)])
 if plot.position.y >= 522:
  return PackedVector2Array([Vector2(center.x, plot.end.y), Vector2(center.x, 640 + (
   floorf(maxf(0.0, plot.position.y - 791) / 112) * 112 + 132 if plot.position.y >= 791 else 0.0))])
 var road_x := 36.0 if center.x < 180 else 353.0
 if center.x < 340 and plot.position.y < 280:
  return PackedVector2Array([Vector2(plot.position.x if road_x == 36 else plot.end.x,
   center.y), Vector2(road_x, center.y)])
 var road_y := 62.0 if plot.position.y < 180 else CROSS
 return PackedVector2Array([Vector2(center.x,
  plot.position.y if road_y < center.y else plot.end.y), Vector2(center.x, road_y)])

static func ore_route(plot: Rect2) -> PackedVector2Array:
 var access := driveway(plot)
 var road := access[1]
 var points := PackedVector2Array([access[0], road])
 if road.y > 600:
  points.append(Vector2(CONNECTOR, road.y))
 elif road.y == 62:
  points.append(Vector2(353, road.y))
  points.append(Vector2(353, CROSS))
 elif road.y > 62 and road.y < CROSS:
  points.append(Vector2(road.x, CROSS))
 if road.y <= CROSS:
  points.append(Vector2(CONNECTOR, CROSS))
 points.append(Vector2(CONNECTOR, PORT_LANE))
 points.append(Vector2(GATE.x, PORT_LANE))
 points.append(GATE)
 return points

static func length(points: PackedVector2Array) -> float:
 var total := 0.0
 for index in range(1, points.size()):
  total += points[index - 1].distance_to(points[index])
 return total

static func pose(points: PackedVector2Array, progress: float) -> Transform2D:
 var distance := length(points) * clampf(progress, 0.0, 1.0)
 for index in range(1, points.size()):
  var start := points[index - 1]
  var finish := points[index]
  var segment := start.distance_to(finish)
  if segment <= 0:
   continue
  if distance <= segment or index == points.size() - 1:
   return Transform2D((finish - start).angle(), start.lerp(finish, distance / segment))
  distance -= segment
 return Transform2D(0.0, points[0])

static func overflow_plot(index: int) -> Rect2:
 return Rect2(58 + (index % 6) * 140,
  791 + floori(float(index) / 6.0) * 112, 116, 92)

static func mine_plot(facilities: Array, id: String) -> Rect2:
 var overflow := 0
 for facility in facilities:
  if facility.get("body") != "earth" or facility.get("type") in ["orbital_platform", "shipyard"]:
   continue
  var site: String = facility.get("surface_site_id", "")
  if facility.get("id") == id:
   return PLOTS.get(site, overflow_plot(overflow))
  if not PLOTS.has(site):
   overflow += 1
 return PLOTS["earth-mine-01"]
