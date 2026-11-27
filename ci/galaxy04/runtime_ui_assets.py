"""Galaxy 0.4 D1 — serve bundled priority-inspector assets over actual
HTTP. The previous Windows CI checked file presence and JS syntax only;
native.html referenced two unregistered routes -> browser HTTP 404.
The handlers are allowlisted and use the existing observer_asset loader.
"""
from pathlib import Path
src=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
runtime=src/"crates/sim_server/src/runtime.rs"
api=src/"crates/sim_server/src/http/api.rs"
r=runtime.read_text(encoding="utf-8")
old='        .route("/observer/station-kit.js", get(api::observer_station_kit_js))'
new=old+'''
        // Galaxy 0.4 D1: modular priority inspector used by native.html.
        .route("/observer/priority-inspector.js", get(api::observer_priority_inspector_js))
        .route("/observer/priority-inspector.css", get(api::observer_priority_inspector_css))'''
if r.count(old)!=1:raise RuntimeError("Expected exactly one Observer route anchor")
runtime.write_text(r.replace(old,new,1),encoding="utf-8")
text=api.read_text(encoding="utf-8")
anchor="/* Approved V5.1 frontend."
if text.count(anchor)!=1:raise RuntimeError("Could not find unique Observer handler boundary")
newhandlers=r'''
// Exact-path allowlist: these are the new native Observer modules.
// Both are also embedded for development when LIVING_SECTOR_UI_DIR is absent.
pub async fn observer_priority_inspector_js() -> impl IntoResponse {
    (
        [
            (axum::http::header::CONTENT_TYPE, "text/javascript; charset=utf-8"),
            (axum::http::header::CACHE_CONTROL, "no-store"),
        ],
        observer_asset(
            "priority-inspector.js",
            include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../observer/priority-inspector.js")),
        ),
    )
}

pub async fn observer_priority_inspector_css() -> impl IntoResponse {
    (
        [
            (axum::http::header::CONTENT_TYPE, "text/css; charset=utf-8"),
            (axum::http::header::CACHE_CONTROL, "no-store"),
        ],
        observer_asset(
            "priority-inspector.css",
            include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../observer/priority-inspector.css")),
        ),
    )
}

'''
api.write_text(text.replace(anchor,newhandlers+anchor,1),encoding="utf-8")
print("Galaxy 0.4 D1: registered HTTP routes for inspector JS and CSS")
