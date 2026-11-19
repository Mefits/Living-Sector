extends Control
## One lightweight vector glyph renderer for the globe, built list and catalog.
## No textures, imported fonts or external assets.
var kind: String = "administrative_center"
var tint: Color = Color("#b6d8de")

func _ready() -> void:
 custom_minimum_size = Vector2(30, 30)
 mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
 paint(self, kind, size * 0.5, minf(size.x, size.y) * 0.40, tint)

static func paint(canvas: CanvasItem, name: String, center: Vector2,
        radius: float, color: Color) -> void:
 var r: float = maxf(3.0, radius)
 var x: float = center.x
 var y: float = center.y
 var stroke: float = maxf(1.3, r * 0.17)
 var dark := Color("#10212c", color.a)
 canvas.draw_rect(Rect2(center - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
  dark, true)
 canvas.draw_rect(Rect2(center - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
  color, false, stroke)
 match name:
  "administrative_center", "station", "colony_construction_dock":
   canvas.draw_rect(Rect2(x-r*0.28,y-r*0.85,r*0.56,r*0.86), color, true)
   canvas.draw_line(Vector2(x-r*0.75,y+r*0.45),Vector2(x+r*0.75,y+r*0.45),color,stroke)
  "mining_rig":
   canvas.draw_line(Vector2(x-r*0.77,y+r*0.6),Vector2(x,y-r*0.72),color,stroke)
   canvas.draw_line(Vector2(x,y-r*0.72),Vector2(x+r*0.77,y+r*0.6),color,stroke)
   canvas.draw_line(Vector2(x-r*0.5,y+r*0.1),Vector2(x+r*0.5,y+r*0.1),color,stroke)
  "spaceport":
   canvas.draw_arc(center,r*0.55,0.0,TAU,22,color,stroke)
   canvas.draw_line(Vector2(x-r*0.8,y),Vector2(x+r*0.8,y),color,stroke)
   canvas.draw_line(Vector2(x,y-r*0.78),Vector2(x,y+r*0.78),color,stroke)
  "farm":
   for offset in [-0.48, 0.0, 0.48]:
    canvas.draw_line(Vector2(x-r*0.75,y+r*offset),
     Vector2(x+r*0.75,y+r*offset),color,stroke)
   canvas.draw_line(Vector2(x,y-r*0.65),Vector2(x,y+r*0.65),color,stroke)
  "refinery":
   canvas.draw_rect(Rect2(x-r*0.7,y-r*0.15,r*1.4,r*0.85),color,true)
   canvas.draw_rect(Rect2(x-r*0.35,y-r*0.8,r*0.25,r*0.8),color,true)
   canvas.draw_rect(Rect2(x+r*0.3,y-r*0.55,r*0.25,r*0.55),color,true)
  "factory":
   canvas.draw_rect(Rect2(x-r*0.7,y-r*0.02,r*1.4,r*0.75),color,true)
   for offset in [-0.5, 0.0, 0.5]:
    canvas.draw_line(Vector2(x+r*offset,y-r*0.72),
     Vector2(x+r*offset,y-r*0.05),color,stroke)
  "power_plant":
   canvas.draw_polyline(PackedVector2Array([
    Vector2(x+r*0.1,y-r*0.82),Vector2(x-r*0.4,y+r*0.1),
    Vector2(x+r*0.1,y+r*0.1),Vector2(x-r*0.1,y+r*0.82),
    Vector2(x+r*0.55,y-r*0.17)]), color, stroke)
  "orbital_platform":
   canvas.draw_arc(center,r*0.57,0,TAU,20,color,stroke)
   canvas.draw_line(Vector2(x-r*0.7,y-r*0.7),
    Vector2(x+r*0.7,y+r*0.7),color,stroke)
  "shipyard":
   canvas.draw_line(Vector2(x-r*0.65,y+r*0.65),
    Vector2(x-r*0.65,y-r*0.65),color,stroke)
   canvas.draw_line(Vector2(x-r*0.7,y-r*0.65),
    Vector2(x+r*0.7,y-r*0.65),color,stroke)
   canvas.draw_line(Vector2(x+r*0.4,y-r*0.65),
    Vector2(x+r*0.4,y+r*0.15),color,stroke)
   canvas.draw_line(Vector2(x-r*0.35,y+r*0.58),
    Vector2(x+r*0.65,y+r*0.58),color,stroke)
  _:
   canvas.draw_line(Vector2(x-r*0.65,y-r*0.65),
    Vector2(x+r*0.65,y+r*0.65),color,stroke)
