# N41 — Observer media provenance and missing station-kit assets

**Status: CODE_UNVERIFIED (source audit; no Godot runtime).** Frozen source: `archive/rust-galaxy-067-reference` @ `6e40615be95cc6ddbabe21c3b94def5c52f8622d`. New Godot work is based on integration PR #128 @ `1e4a1e9f34fff7313ce176107890ecdbe25fc85a`; checkpoint remains untouched.

## Findings from frozen Git tree (not from the old N37 inventory)

1. `native/observer/` contains **41 tracked blobs** and **zero physical image/audio/font blobs** with conventional media extensions. This is distinct from the 97 client assets inventoried in N37.
2. `native/observer/assets/station-kit/manifest.json` lists **16** intended SVG module paths under `modules/`; **none** are tracked in that frozen subtree. The README describes 3 station cores and 3 slot-state graphics as a production list, not delivered files. **Do not invent or silently load these images.**
3. `native/observer/station-kit.js` renders flat station symbols through Canvas primitives; its `visualStationTier` is a *visual heuristic*, not an authoritative T1/T2/T3 game upgrade. Do not port it as gameplay tier logic.
4. Observer CSS uses system font stacks. `native/observer/package.json` contains no runtime dependency declarations and no bundled binary fonts. Inline CSS/Canvas artwork still needs provenance review; absence of files does not establish licensing rights.
5. `native/observer/index.html` contains `/observer/native.html` and `/observer/v51-live-adapter.js` links: these are **application routes**, not evidence of bundled media or external assets. Browser network dependencies and generated DOM graphics must be reviewed separately before packaging.

## Transfer gates

- Do not copy `client_bevy` media, embedded artwork, or missing station-kit SVGs into Godot without independently verified origin and rights. Root MIT licensing is not automatic proof of third-party media rights.
- Preserve Godot's existing native `CanvasItem._draw()` / `draw_polygon()` style where possible for flat shapes; for thousands of agents use batched drawing rather than a node per symbol. No external graphics plugin required (Godot built-ins; MIT Godot engine).
- Keep display-only station tiers separate from authoritative station slots and construction.
- Keep any future placeholder art clearly labelled as *new original artwork*, not recovered Rust assets.
- Run `python godot/tools/audit_observer_assets.py --json` from a full Git checkout. It is read-only, requires only Python stdlib and Git, and fails if declared manifest assets are missing or paths duplicated. The expected result on the frozen tree is a **non-zero exit**, because the 16 declared SVGs are absent. That failure is a useful inventory finding, not a broken Godot game.
- Future integration tests must not fetch remote assets or write user saves.

## Evidence / scope

The 41-path Git tree, `manifest.json`, `README.md`, `station-kit.js`, `styles.css`, `index.html` and `package.json` were inspected through GitHub connector. Expected inventory counts were checked against the frozen Git tree. **The new Python checker has not been executed and no Godot smoke has run.** No assets were copied, no Rust source was modified, no P0/P1/P2 VERIFIED counter is increased.

Next work: resolve provenance of embedded graphics and any external URLs; review client media N37 separately. Do not conflate manifest placeholders with delivered images.
