extends RefCounted
## Backwards-compatible adapter for existing Sol N43 projection tests.
## Production code now uses physical_assets_projection.gd for every system.
const Shared = preload("res://scripts/view/physical_assets_projection.gd")

static func build(world: Dictionary) -> Dictionary:
    return Shared.build(world)

static func live_status(asset: Dictionary,
        live_facilities: Dictionary) -> Dictionary:
    return Shared.live_status(asset, live_facilities)
