// Keep the optional telemetry source editable and the served app.js self-contained.
import {readFileSync,writeFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname,join} from "node:path";
const dir=dirname(fileURLToPath(import.meta.url));
const read=n=>readFileSync(join(dir,n),"utf8");
const beg="/* BEGIN GENERATED TELEMETRY BUNDLE */",end="/* END GENERATED TELEMETRY BUNDLE */";
const cssBegin="/* BEGIN GENERATED TELEMETRY CSS */",cssEnd="/* END GENERATED TELEMETRY CSS */";
const model=read("telemetry-model.js").replace(/^export /gm,"").trimEnd();
const ui=read("telemetry-ui.js").replace(/import \{[\s\S]*?\} from "\/observer\/telemetry-model\.js";\s*/,"").replace(/^export /gm,"").trimEnd();
if(ui.includes('from "/observer/telemetry-model.js"'))throw Error("telemetry import not removed");
const newBundle=[beg,model,ui,end].join("\n\n");
function replaceBetween(text,a,b,replacement){const i=text.indexOf(a),j=text.indexOf(b,i);if(i<0||j<0)throw Error("Missing telemetry bundle marker");return text.slice(0,i)+replacement+text.slice(j+b.length)}
const app=replaceBetween(read("app.js"),beg,end,newBundle);
const styles=replaceBetween(read("styles.css"),cssBegin,cssEnd,cssBegin+"\n"+read("telemetry.css").trimEnd()+"\n"+cssEnd);
const mode=process.argv[2]||"--check";
for(const [name,next] of [["app.js",app],["styles.css",styles]]) {
 const original=read(name);
 if(mode==="--check"&&original!==next)throw Error(name+" telemetry bundle out of date");
 if(mode==="--write"&&original!==next)writeFileSync(join(dir,name),next);
}
if(!["--check","--write"].includes(mode))throw Error("Use --check / --write");
if(mode==="--check")console.log("Telemetry bundle up to date");
