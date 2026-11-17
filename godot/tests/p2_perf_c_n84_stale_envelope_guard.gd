extends SceneTree
## Source-level negative regression for N84 envelope invalidation.
## The cached token/cardinality cannot prove that another row's transit
## or identity remained unchanged within a proposal.
func _initialize() -> void:
    var file := FileAccess.open("res://scripts/sim/phase2/unified_ship_phase.gd", FileAccess.READ)
    assert(file != null, "N84 source missing")
    var source: String = file.get_as_text()
    var start: int = source.find("static func preview_depart(")
    assert(start >= 0, "preview_depart missing")
    var body: String = source.substr(start)
    assert(body.contains("for id in world[\"ships\"]:"), "live fleet envelope scan missing")
    assert(body.contains("invalid_ship_identity"), "stale identity must fail")
    assert(body.contains("invalid_ship_transit"), "stale transit must fail")
    assert(body.contains("max_token = maxi("), "new transit token must be observed")
    assert(not body.contains("if cached:"), "token/size-only cache can accept stale transit")
    assert(body.contains("state.restore([world[\"ships\"][ship_id]])"), "selected ship must be detached")
    print("PASS p2_perf_c_n84_stale_envelope_guard source negative")
    quit()
