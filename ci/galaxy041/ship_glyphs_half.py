"""Galaxy 0.4.1 UI-only compact ships for orbital/system map.

Keep simulation ship geometry and all economic/pathfinding code untouched.
Apply after all Galaxy 0.4/0.4.1 Observer patches. Every displayed ship is
scaled to 50%, including individually docked ships and aggregated markers.
Slightly tighter dock spacing/marker occupancy, but keep generous hit boxes.
"""
from pathlib import Path

root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2/observer"
app=root/"app.js"
model=root/"model.js"
tests=root/"model.test.mjs"

def one(path, before, after):
    original=path.read_text(encoding="utf8")
    count=original.count(before)
    if count!=1:
        raise RuntimeError(f"ship-glyph-50% overlay mismatch, {count} matches in {path.name}: {before!r}")
    path.write_text(original.replace(before,after,1),encoding="utf8")

one(model,
    """export function mapIconScale(zoom) {
  return Math.min(2.7, Math.max(0.62, Math.sqrt(Math.max(0.1, zoom))));
}
""",
    """export function mapIconScale(zoom) {
  return Math.min(2.7, Math.max(0.62, Math.sqrt(Math.max(0.1, zoom))));
}

// Only orbital-map SHIP glyphs shrink; other map markers, UI panels,
// and actual world-space ship positions do not change.
export function shipMapGlyphScale(iconScale) {
  return iconScale * 0.5;
}
""")

one(app,
    """worldGridStep, mapIconScale,
  groupFacilitiesByLocation,""",
    """worldGridStep, mapIconScale, shipMapGlyphScale,
  groupFacilitiesByLocation,""")

one(app,
    """  const iconScale=Math.min(1.2,mapIconScale(s.zoom));
  const planetScale=Math.min(2.3,mapIconScale(s.zoom)*1.15);""",
    """  const iconScale=Math.min(1.2,mapIconScale(s.zoom));
  const shipIconScale=shipMapGlyphScale(iconScale);
  const planetScale=Math.min(2.3,mapIconScale(s.zoom)*1.15);""")

# Parked ships: geometry, anchor spacing, overlap bookkeeping and target.
one(app,
    """            x:hub.at.x+(31+col*20)*iconScale,
            y:hub.at.y+(10+row*21)*iconScale""",
    """            x:hub.at.x+(23+col*14)*iconScale,
            y:hub.at.y+(10+row*15)*iconScale""")
one(app,
    """          withMapScale(at,Math.min(iconScale,1.8),()=>drawShip(ship,at,""",
    """          withMapScale(at,shipIconScale,()=>drawShip(ship,at,""")
one(app,
    """          markGlyph(at,10*iconScale);
          askLabel("parked-"+ship.id,at,shipDisplayName(ship),
            "#c2dce4",selected?0:5,13,140);
          addTarget("ship",ship.id,at.x,at.y,Math.max(12,12*iconScale),""",
    """          markGlyph(at,10*shipIconScale);
          askLabel("parked-"+ship.id,at,shipDisplayName(ship),
            "#c2dce4",selected?0:5,9,140);
          addTarget("ship",ship.id,at.x,at.y,Math.max(10,10*shipIconScale),""")

# Ship groups: scale the single cluster glyph too, not just solo ships.
one(app,
    """        withMapScale(group,Math.min(iconScale,1.8),()=>
          drawShip(group.members[0].ship,group,""",
    """        withMapScale(group,shipIconScale,()=>
          drawShip(group.members[0].ship,group,""")
one(app,
    """        markGlyph(group,12*iconScale);
        askLabel("ships-"+group.id,group,ids.length+" корабля",
          "#c2dce4",selected?0:5,16,118);
        addTarget("ship_group",group.id,group.x,group.y,
          Math.max(17,16*iconScale),""",
    """        markGlyph(group,12*shipIconScale);
        askLabel("ships-"+group.id,group,ids.length+" корабля",
          "#c2dce4",selected?0:5,10,118);
        addTarget("ship_group",group.id,group.x,group.y,
          Math.max(12,12*shipIconScale),""")

# Independent in-flight and idle glyphs.
one(app,
    """        withMapScale(at,iconScale,()=>drawShip(ship,at,
          factionColor(ship.faction_id,s.index),selected,""",
    """        withMapScale(at,shipIconScale,()=>drawShip(ship,at,
          factionColor(ship.faction_id,s.index),selected,""")
one(app,
    """        markGlyph(at,11*iconScale);
        askLabel("ship-"+ship.id,at,shipDisplayName(ship),
          "#c2dce4",selected?0:3,16,145);
        addTarget("ship",ship.id,at.x,at.y,
          Math.max(selected?15:12,12*iconScale),""",
    """        markGlyph(at,11*shipIconScale);
        askLabel("ship-"+ship.id,at,shipDisplayName(ship),
          "#c2dce4",selected?0:3,10,145);
        addTarget("ship",ship.id,at.x,at.y,
          Math.max(selected?12:10,10*shipIconScale),""")

test_text=tests.read_text(encoding="utf8")
if "shipMapGlyphScale" in test_text:
    raise RuntimeError("Ship size regression test already injected")
tests.write_text(test_text+'''
test("Galaxy 0.4.1 orbital ship glyphs use 50% scale, without resizing stations", async () => {
  const {shipMapGlyphScale} = await import("./model.js");
  assert.equal(shipMapGlyphScale(1),0.5);
  assert.equal(shipMapGlyphScale(0.62),0.31);
  assert.equal(shipMapGlyphScale(1.2),0.6);
  const {readFile} = await import("node:fs/promises");
  const app = await readFile(new URL("./app.js",import.meta.url),"utf8");
  assert.ok(app.includes("const shipIconScale=shipMapGlyphScale(iconScale);"));
  assert.equal((app.match(/withMapScale\\((?:at|group),shipIconScale,/g)||[]).length,3,
    "docked, clustered and individual ships must all use the same reduction");
  assert.ok(app.includes("withMapScale(at,iconScale,()=>drawFacilityHub"),
    "station icons must retain their previous size");
});
''',encoding="utf8")

print("Galaxy 0.4.1: all ship map glyphs 50%; planet/station sprites unchanged; selection stays usable")
