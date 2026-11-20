extends RefCounted
## Top-down modules drawn in district pixels. One sun vector for the whole district.
const GROUND = ["administrative_center", "farm", "mining_rig", "refinery",
 "factory", "power_plant", "spaceport"]
const PAPER = Color("#c2c2ad")
const STEEL = Color("#667876")
const OCHRE = Color("#cd9b54")
const DARK = Color("#303634")
const YARD = Color("#797a68")

static func terrain(c: CanvasItem, area: Vector2) -> void:
 c.draw_rect(Rect2(Vector2.ZERO, area), Color("#646b4c"))
 var wet := PackedVector2Array([Vector2(945, 0), Vector2(area.x, 0),
  area, Vector2(954, area.y), Vector2(937, 498), Vector2(952, 390),
  Vector2(936, 273), Vector2(950, 176)])
 c.draw_colored_polygon(wet, Color("#4c6457"))
 c.draw_polyline(PackedVector2Array([Vector2(955, 0), Vector2(964, 176),
  Vector2(949, 273), Vector2(964, 390), Vector2(949, 498),
  Vector2(965, area.y)]), Color("#536e62"), 8, true)
 var rng := RandomNumberGenerator.new()
 rng.seed = 21018
 for i in range(2700):
  var p := Vector2(rng.randf_range(1, area.x - 4), rng.randf_range(1, area.y - 4))
  var tone := Color("#84906a") if i % 3 == 0 else Color("#494f3b")
  tone.a = rng.randf_range(0.10, 0.29)
  c.draw_rect(Rect2(p, Vector2(rng.randf_range(2, 12), rng.randf_range(1, 5))), tone)
 for i in range(340):
  var p := Vector2(rng.randf_range(6, 874), rng.randf_range(6, area.y - 7))
  if p.x < 24 or p.y < 36 or (p.x > 625 and p.y > 590) or (
    p.y > 292 and p.y < 344 and (p.x < 328 or p.x > 543)):
   var radius := rng.randf_range(2, 8)
   c.draw_circle(p + Vector2(3, 3), radius, Color("#434c36"))
   c.draw_circle(p, radius, Color("#536041").lerp(Color("#768157"), rng.randf()))
 for y in [62, 371, 640]:
  road(c, Vector2(35, y), Vector2(917, y))
 for x in [36, 917]:
  road(c, Vector2(x, 63), Vector2(x, area.y - 21))
 road(c, Vector2(353, 63), Vector2(353, 371))
 road(c, Vector2(538, 371), Vector2(538, 640))
 road(c, Vector2(538, 449), Vector2(548, 449))
 # Gravel approaches, kept outside the buildable footprints.
 for x in [112, 251, 468, 624, 789]:
  c.draw_line(Vector2(x, 72), Vector2(x, 82), Color("#898774"), 16)
 for x in [136, 318, 502]:
  c.draw_line(Vector2(x, 380), Vector2(x, 400), Color("#898774"), 11)
 if area.y > 670:
  road(c, Vector2(36, 672), Vector2(917, 672))

static func road(c: CanvasItem, a: Vector2, b: Vector2) -> void:
 c.draw_line(a, b, Color("#8a8975"), 22)
 c.draw_line(a, b, Color("#444c48"), 16)
 var dir := (b - a).normalized()
 for d in range(4, int(a.distance_to(b)) - 9, 18):
  c.draw_line(a + dir * d, a + dir * (d + 8), Color("#a19c7d"), 1)

static func empty_plot(c: CanvasItem, r: Rect2, id: String) -> void:
 var farming := "farm" in id or id == "earth-common-01"
 c.draw_rect(r, Color("#6b7452") if farming else Color("#70725a"))
 c.draw_rect(r, Color("#85846b"), false, 1)
 if farming:
  for x in range(8, int(r.size.x) - 4, 9):
   c.draw_line(r.position + Vector2(x, 5), r.position + Vector2(x, r.size.y - 5),
    Color("#777e59"), 1)
 for v in [r.position, r.end - Vector2(3, 3),
  Vector2(r.end.x - 3, r.position.y), Vector2(r.position.x, r.end.y - 3)]:
  c.draw_rect(Rect2(v, Vector2(3, 3)), Color("#b4ad88"))

static func panel(c: CanvasItem, r: Rect2, tint: Color) -> void:
 c.draw_rect(Rect2(r.position + Vector2(5, 7), r.size), Color("#252d2b99"))
 c.draw_rect(r.grow(1), DARK)
 c.draw_rect(r, tint.darkened(0.24))
 c.draw_rect(Rect2(r.position, r.size - Vector2(0, 4)), tint)
 c.draw_line(r.position + Vector2(1, 1), r.position + Vector2(r.size.x - 1, 1),
  tint.lightened(0.28), 1)

static func roof(c: CanvasItem, p: Vector2, s: Vector2, tint: Color) -> void:
 var r := Rect2(p, s)
 panel(c, r, tint)
 for x in range(6, int(s.x) - 2, 10):
  c.draw_line(p + Vector2(x, 3), p + Vector2(x, s.y - 5), tint.darkened(0.13), 1)
 for x in range(12, int(s.x) - 9, 22):
  panel(c, Rect2(p + Vector2(x, 8), Vector2(7, 5)), tint.darkened(0.24))

static func tank(c: CanvasItem, p: Vector2, radius: float, tint: Color) -> void:
 c.draw_circle(p + Vector2(4, 5), radius + 1, Color("#292e2990"))
 c.draw_circle(p, radius + 1, DARK, true, -1, true)
 c.draw_circle(p, radius, tint, true, -1, true)
 c.draw_arc(p, radius - 2, PI, PI * 1.69, 11, tint.lightened(0.3), 1.5, true)
 c.draw_circle(p, maxf(2, radius * 0.27), tint.darkened(0.35))

static func pad_anchor(r: Rect2) -> Vector2:
 return r.position + Vector2(128, 67)

static func building(c: CanvasItem, r: Rect2, kind: String, ship: Texture2D,
  is_preview: bool = false) -> void:
 var p := r.get_center()
 if kind != "farm":
  c.draw_rect(r, YARD)
  c.draw_rect(r.grow(-3), YARD.darkened(0.14), false, 1)
 match kind:
  "administrative_center":
   roof(c, p + Vector2(-42, -15), Vector2(25, 31), STEEL)
   roof(c, p + Vector2(17, -15), Vector2(25, 31), STEEL)
   panel(c, Rect2(p + Vector2(-21, -7), Vector2(42, 12)), PAPER.darkened(0.2))
   roof(c, p + Vector2(-17, -25), Vector2(34, 47), PAPER)
   panel(c, Rect2(p + Vector2(-10, 17), Vector2(20, 15)), Color("#51696c"))
   c.draw_rect(Rect2(p + Vector2(-6, 29), Vector2(12, 3)), OCHRE)
  "farm":
   empty_plot(c, r, "farm")
   var left := r.position + Vector2(8, 9)
   for i in range(4):
    var row := Rect2(left + Vector2(i * (r.size.x - 15) / 4, 0),
     Vector2((r.size.x - 15) / 4 - 4, r.size.y - 17))
    c.draw_rect(row, Color("#596744") if i % 2 == 0 else Color("#74794d"))
    for j in range(4, int(row.size.x), 5):
     c.draw_line(row.position + Vector2(j, 2), row.position + Vector2(j, row.size.y - 2),
      Color("#929058"), 1.3)
   for j in range(3):
    var q := p + Vector2(-37 + j * 18, -27)
    panel(c, Rect2(q, Vector2(14, 44)), Color("#a5b5a0"))
    for y in range(4, 42, 5):
     c.draw_line(q + Vector2(0, y), q + Vector2(14, y), Color("#617e77"), 1)
    c.draw_line(q + Vector2(7, 2), q + Vector2(7, 42), Color("#d0cfac"), 1)
   roof(c, p + Vector2(27, 11), Vector2(19, 17), Color("#9d885f"))
  "mining_rig":
   c.draw_rect(r.grow(-6), Color("#776950"))
   var bit := p + Vector2(-21, 0)
   for i in range(3):
    c.draw_circle(bit, 29 - i * 6, Color("#8c7858").darkened(i * 0.12))
   c.draw_line(bit + Vector2(-18, 14), bit + Vector2(12, -19), OCHRE, 5)
   c.draw_circle(bit, 8, DARK)
   tank(c, bit, 5, OCHRE)
   roof(c, p + Vector2(12, -23), Vector2(36, 16), Color("#a88961"))
   c.draw_line(bit, p + Vector2(35, 14), DARK, 7)
   for i in range(3):
    panel(c, Rect2(p + Vector2(21 + i * 9, 11), Vector2(7, 13)), STEEL)
  "refinery":
   roof(c, p + Vector2(-51, -26), Vector2(57, 49), Color("#a5a18e"))
   c.draw_polyline(PackedVector2Array([p + Vector2(-4, 6), p + Vector2(43, 6),
    p + Vector2(43, -16), p + Vector2(23, -16)]), DARK, 5)
   c.draw_line(p + Vector2(3, 6), p + Vector2(43, 6), OCHRE, 2)
   tank(c, p + Vector2(18, -18), 10, PAPER)
   tank(c, p + Vector2(44, -18), 13, Color("#b1b4a4"))
   tank(c, p + Vector2(36, 20), 11, STEEL)
   tank(c, p + Vector2(-39, 14), 5, DARK.lightened(0.15))
  "factory":
   for i in range(3):
    roof(c, p + Vector2(-49 + i * 22, -26), Vector2(21, 52), Color("#856f58").lightened(i * 0.06))
   roof(c, p + Vector2(17, -28), Vector2(31, 19), STEEL)
   for i in range(3):
    panel(c, Rect2(p + Vector2(23 + i * 8, 6), Vector2(5, 16)),
     Color("#bc9d70").darkened(i * 0.1))
  "power_plant":
   roof(c, p + Vector2(-46, -25), Vector2(30, 52), PAPER.darkened(0.2))
   tank(c, p + Vector2(-28, -9), 6, STEEL)
   for j in range(2):
    for i in range(3):
     var q := p + Vector2(-5 + i * 17, -26 + j * 27)
     panel(c, Rect2(q, Vector2(14, 21)), Color("#475c65"))
     for y in [5, 10, 15]:
      c.draw_line(q + Vector2(0, y), q + Vector2(14, y), Color("#78918e"), 1)
  "spaceport":
   var anchor := pad_anchor(r)
   c.draw_circle(anchor, 32, DARK, true, -1, true)
   c.draw_circle(anchor, 28, Color("#4e5653"), true, -1, true)
   var second := anchor + Vector2(167, 0)
   c.draw_circle(second, 20, DARK, true, -1, true)
   c.draw_arc(second, 17, 0, TAU, 28, OCHRE.darkened(0.25), 1.5, true)
   for i in range(4):
    c.draw_arc(anchor, 29, i * TAU / 4 + 0.15, i * TAU / 4 + 1.42,
     12, OCHRE, 2.0, true)
   c.draw_line(anchor - Vector2(21, 0), anchor + Vector2(21, 0), Color("#848776"), 1)
   c.draw_line(anchor - Vector2(0, 21), anchor + Vector2(0, 21), Color("#848776"), 1)
   roof(c, p + Vector2(-28, -41), Vector2(53, 49), STEEL)
   roof(c, p + Vector2(-16, -53), Vector2(30, 17), PAPER.darkened(0.12))
   for j in range(3):
    for i in range(6):
     panel(c, Rect2(p + Vector2(-59 + i * 19, 39 + j * 10), Vector2(15, 5)),
      [OCHRE, STEEL, PAPER][(i + j * 2) % 3].darkened(0.15))
   if ship != null and not is_preview:
    c.draw_texture_rect(ship, Rect2(anchor - Vector2(5.5, 12), Vector2(11, 24)), false)

static func construction(c: CanvasItem, r: Rect2, kind: String) -> void:
 c.draw_rect(r, Color("#7f7760"))
 c.draw_rect(r.grow(-5), Color("#ad9a69"), false, 1)
 var p := r.get_center()
 panel(c, Rect2(p - Vector2(23, 11), Vector2(46, 22)), Color("#9b917b"))
 for i in range(4):
  c.draw_line(p + Vector2(-20 + i * 11, -9), p + Vector2(-13 + i * 11, 8), OCHRE, 2)
 if kind == "spaceport":
  c.draw_arc(pad_anchor(r), 28, 0, TAU, 36, OCHRE, 1.5, true)

static func preview(c: CanvasItem, r: Rect2, kind: String, ship: Texture2D) -> void:
 building(c, r.grow(-3), kind, ship, true)
 c.draw_rect(r, Color("#a8c88a38"))
