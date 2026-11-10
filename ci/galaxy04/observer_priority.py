"""Galaxy 0.4 C: install priority-first Observer inspector from independent,
testable JavaScript module. No changes to the native server or simulation.

The user can always open collapsed engineering details. Existing star-system
and grouped-ship inspectors remain as conservative fallbacks.
"""
from pathlib import Path
import shutil

checkout=Path(__file__).resolve().parents[2]
root=checkout/"work/source/Living-Sector-Galaxy-0.2"
observer=root/"observer"

def replace_once(path,old,new):
    s=path.read_text(encoding="utf-8")
    n=s.count(old)
    if n != 1:raise RuntimeError(f"Observer C expected one anchor in {path}, got {n}")
    path.write_text(s.replace(old,new,1),encoding="utf-8")

for name in ("priority-inspector.js","priority-inspector.css","priority-inspector.test.mjs"):
    src=checkout/"observer"/name
    if not src.is_file():raise RuntimeError(f"Missing C module {src}")
    shutil.copyfile(src,observer/name)

replace_once(observer/"app.js",
    'import {drawStationComplex,visualStationTier,stationScale,stationReveal} from "/observer/station-kit.js";',
    'import {drawStationComplex,visualStationTier,stationScale,stationReveal} from "/observer/station-kit.js";\n'
    'import {renderPriorityInspector} from "/observer/priority-inspector.js";')

replace_once(observer/"app.js",
    '  const type = s.selection.type;\n  const typeNames = {',
    '''  const type = s.selection.type;
  // Galaxy 0.4 C: important server facts appear before technical names and
  // engineering fields. Unsupported selections retain the legacy inspector.
  if(renderPriorityInspector(els.inspectorBody,type,entity,{
    report:s.report,index:s.index,
    select:(kind,id)=>{s.selection={type:kind,id};renderInspector();}
  })){
    els.inspectorBody.scrollTop=previousScroll;
    return;
  }
  const typeNames = {''')
# Keep open technical details expanded on the same selection while live data
# refreshes, otherwise a periodic render repeatedly collapses the panel.
replace_once(observer/"app.js",
    '  const previousScroll = selectionKey && selectionKey === lastInspectorSelection\n'
    '    ? els.inspectorBody.scrollTop : 0;',
    '  const previousScroll = selectionKey && selectionKey === lastInspectorSelection\n'
    '    ? els.inspectorBody.scrollTop : 0;\n'
    '  const keepTechnicalOpen = Boolean(selectionKey && selectionKey === lastInspectorSelection\n'
    '    && els.inspectorBody.querySelector("details.priority-technical[open]"));')
replace_once(observer/"app.js",
    '    els.inspectorBody.scrollTop=previousScroll;\n    return;\n  }\n  const typeNames = {',
    '    const technical = els.inspectorBody.querySelector("details.priority-technical");\n'
    '    if(keepTechnicalOpen && technical)technical.open=true;\n'
    '    els.inspectorBody.scrollTop=previousScroll;\n    return;\n  }\n  const typeNames = {')

replace_once(observer/"native.html",
    '  <link rel="stylesheet" href="/observer/styles.css">',
    '  <link rel="stylesheet" href="/observer/styles.css">\n'
    '  <link rel="stylesheet" href="/observer/priority-inspector.css">')
print("Galaxy 0.4 C: priority-first selection module, CSS and tests installed")
