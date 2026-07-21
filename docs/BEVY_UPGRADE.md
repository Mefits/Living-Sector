# Bevy 0.14 → 0.18 upgrade plan

Status: **deferred** (open). Symptom that motivated it: bevy_hanabi 0.13
on macOS Metal causes 30s GPU stalls during camera movement on
saves with many active emitters (~282 ship trails). Workaround: leave
`HanabiPlugin` enabled but accept the freezes, OR disable hanabi
entirely (samply confirmed both render + main threads parked in
`__psynch_cvwait` waiting on the GPU when stalls fire).

## Why this is non-trivial

Four versions of Bevy churn between 0.14 and 0.18, and our
`client_bevy` deeply touches every layer that changed:

| Bevy step | What broke for us | Approx scope |
|---|---|---|
| 0.14 → 0.15 | `*Bundle` types deprecated → Required Components; `EventReader::iter` → `read`; `Time::delta_seconds` → `delta_secs`; `Query::get_single` → `single`; `EntityCommands::despawn_recursive` removed (`despawn` now recursive by default) | ~50 sites, mostly mechanical |
| 0.15 → 0.16 | GPU-driven rendering, retained render world. `MaterialPlugin`'s extract / prepare interface changed substantially. Custom shaders (`PlanetMaterial`, `NebulaMaterial`, `HaloMaterial`, `CloudMaterial`, `StarfieldMaterial`) need their `RenderAsset` / `AsBindGroup` paths reviewed. `VertexAttributeValues` access pattern changed. | The hardest version to cross. |
| 0.16 → 0.17 | UI / asset system churn, additional Required Components fallout, `bevy_audio::Volume::new` removed (now `Volume::Linear` etc.) | Moderate |
| 0.17 → 0.18 | Continued required-components & query API refinements; `bevy_egui` Result-returning `ctx_mut` (egui multi-window support); some hanabi `Modifier` struct field additions (`blend`, `mask`) | Moderate |

Compatible ecosystem versions for Bevy 0.18:

- `bevy = "0.18"` (currently 0.18.1)
- `bevy_egui = "0.39"` (currently 0.39.1)
- `bevy_hanabi = "0.18"`
- `egui_extras = "0.34"` (matches bevy_egui 0.39's egui)
- rustc ≥ 1.92 — see `rust-toolchain.toml` (we pin `stable`)

## Surveyed error categories (from a one-shot 0.14 → 0.18 attempt)

156 errors total when bumping versions in one shot:

```
 36 mismatched types (mostly cascading from missing Bundle types)
 21 *Bundle types removed (MaterialMesh, Scene, Audio, ParticleEffect)
 16 .get_single() → .single() / get_single_mut → single_mut
 14 EguiContexts methods now return Result (wants_pointer_input,
    wants_keyboard_input, is_pointer_over_area, layer_painter)
  6 Color::from(f32) removed — explicit Color::srgb(...) etc.
  6 Gradient::new removed (hanabi)
  6 method-arity mismatch (3 args → 4)
  4 Volume::new removed (audio)
  4 EngineTrailEffect / ParticleEffectBundle gone (hanabi 0.18)
  4 .delta_seconds() → .delta_secs()
  4 .despawn_recursive() → .despawn()
  3 ColorOverLifetimeModifier needs `blend` and `mask` fields
  3 Spawner type removed (hanabi 0.18 uses different spawner API)
  3 EventReader / EventWriter import path moved
  2 VertexAttributeValues now private — use Mesh::attribute()
  2 ShaderRef import moved
  ...
```

## Recommended staging

Don't do it big-bang. Stage by Bevy version, with a working
checkpoint after each:

1. **0.14 → 0.15** (~half day)
   - Bump `bevy = "0.15"`, find compat `bevy_egui` (`0.31` or `0.32`)
     and `bevy_hanabi` (`0.14`).
   - sed rename: `get_single → single`, `get_single_mut → single_mut`,
     `delta_seconds → delta_secs`, `despawn_recursive → despawn`,
     `EventReader::iter → read`.
   - Bundle migration: every `MaterialMeshBundle`, `SceneBundle`,
     `AudioBundle`, `ParticleEffectBundle` spawn site → tuple of
     Required Components. Mechanical but tedious.
   - Test: run client, click around, confirm no visual regressions.

2. **0.15 → 0.16** (~full day, the hardest step)
   - Bump versions, find compat `bevy_egui` / `bevy_hanabi`.
   - Custom material plugins (`PlanetMaterial`, `NebulaMaterial`,
     `HaloMaterial`, `CloudMaterial`, `StarfieldMaterial`) need
     review against the GPU-driven render world. Likely breaking
     change in how `extract` and `prepare` are wired.
   - hanabi 0.14 → 0.15: `Spawner` API and `Modifier` struct fields
     changed.
   - Test particle trails, planet shaders, sun corona, starfield,
     nebula clouds.

3. **0.16 → 0.17** (~half day)
   - Audio API: `Volume::new` → `Volume::Linear` / `Volume::Decibels`.
   - More Required Components churn.

4. **0.17 → 0.18** (~half day)
   - bevy_egui 0.39's `EguiContexts::ctx_mut` returns `Result` now.
     Wrap every call site: `if let Ok(ctx) = egui_ctx.ctx_mut() { ... }`
     or `egui_ctx.try_ctx_mut().ok().is_some_and(|c| ...)`.
   - Hanabi 0.18 new `ColorOverLifetimeModifier { blend, mask }`
     fields.

5. **Verify Metal stall fixed**
   - Reload the same save that was freezing.
   - Move camera around, watch FPS panel + slow-frame logs.
   - If freeze gone → wgpu fix paid off.

## What's already done

- `rust-toolchain.toml` pinned to `stable` so the Homebrew rustc
  doesn't shadow rustup's newer one (we hit this when first trying
  the upgrade — Homebrew shipped 1.87, rustup had 1.95).
- Slow-tick + slow-frame diagnostics in `sim::tick_sim` and
  `main::frame_pulse` — useful regardless, will help diagnose any
  regressions during the staged upgrade.
- `spawn_mirror_entities` defensively takes
  `Option<Res<EngineTrailEffect>>` so disabling `HanabiPlugin` is a
  one-comment toggle (used while debugging the GPU stall).

## Workaround until upgrade lands

If the freezes are intolerable on a save and you can't wait for the
upgrade, comment out `HanabiPlugin` + the three `build_*_effect`
Startup systems + the four hanabi `Update` systems in
`render/mod.rs` (RenderPlugin::build). Visual cost: no engine
trails, no explosion particles, no gate flashes. Sim and economy
unaffected.
