// Bundle the standalone strategy UI into the two already-served Observer assets.
// The Rust server deliberately exposes only /observer/{app.js,model.js,styles.css,index.html}.
// Keep the Rust router untouched so UI branches are independent from core work.
import {readFileSync, writeFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {join, dirname} from "node:path";

const dir = dirname(fileURLToPath(import.meta.url));
const read = name => readFileSync(join(dir, name), "utf8");
const JS_START = "/* BEGIN GENERATED STRATEGY BUNDLE */";
const JS_END = "/* END GENERATED STRATEGY BUNDLE */";
const CSS_START = "/* BEGIN GENERATED STRATEGY CSS */";
const CSS_END = "/* END GENERATED STRATEGY CSS */";

function insert(old, opening, closing, generated, anchor) {
  const start = old.indexOf(opening);
  if (start !== -1) {
    const last = old.indexOf(closing, start);
    if (last < 0) throw new Error("Missing bundle end marker: " + closing);
    return old.slice(0, start) + generated + old.slice(last + closing.length);
  }
  if (!old.includes(anchor)) throw new Error("Missing insertion anchor: " + anchor);
  return old.replace(anchor, generated + "\n" + anchor);
}
function compiledApp() {
  const model = read("strategy-model.js").replace(/^export /gm, "").trimEnd();
  const ui = read("strategy-ui.js")
    .replace(/import \{[\s\S]*?\} from "\/observer\/strategy-model\.js";\s*/, "")
    .replace(/^export /gm, "").trimEnd();
  if (ui.includes('from "/observer/strategy-model.js"')) {
    throw new Error("Unremoved strategy model import");
  }
  const bundle = [JS_START, model, ui, JS_END].join("\n\n");
  const app = read("app.js")
    .replace('import {initStrategyPanel, openStrategyForFaction} from "/observer/strategy-ui.js";\n', "");
  return insert(app, JS_START, JS_END, bundle,
    "wireControls();\ninitStrategyPanel({getFactions: () => list(s.report?.factions)});");
}
function compiledCSS() {
  const css = read("strategy.css").trimEnd();
  const bundle = [CSS_START, css, CSS_END].join("\n");
  const styles = read("styles.css");
  if (!styles.includes(CSS_START)) return styles.trimEnd() + "\n\n" + bundle + "\n";
  return insert(styles, CSS_START, CSS_END, bundle, CSS_END);
}
const mode = process.argv[2] || "--check";
if (!["--write", "--check"].includes(mode)) throw new Error("Use --write or --check");
for (const [filename, content] of [
  ["app.js", compiledApp()], ["styles.css", compiledCSS()]
]) {
  const old = read(filename);
  if (mode === "--check" && content !== old) {
    throw new Error(filename + " is out of date; run node observer/build-strategy.mjs --write");
  }
  if (mode === "--write" && content !== old) {
    writeFileSync(join(dir, filename), content);
    process.stdout.write("Updated observer/" + filename + "\n");
  }
}
if (mode === "--check") process.stdout.write("Strategy bundle is up to date\n");
