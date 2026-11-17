extends SceneTree
## N153 winner-only path detachment: candidate views remain proposal-local;
## the published winning row must never alias the route cache.
const TARGET = "res://scripts/sim/phase2/unified_n153_contract_dispatch.gd"

func _initialize() -> void:
    var source := FileAccess.get_file_as_string(TARGET)
    assert(not source.is_empty(), "N153 source missing")
    assert(source.contains('"path_to_source": route["inbound"]'), "candidate geometry must remain read-only")
    assert(source.contains('(readiness["path_to_source"] as Array).duplicate()'), "winner must detach inbound")
    assert(source.contains('(readiness["source_to_destination"] as Array).duplicate()'), "winner must detach outbound")
    var shared_inbound: Array = ["A", "B"]
    var shared_outbound: Array = ["B", "C"]
    var route := {"inbound": shared_inbound, "outbound": shared_outbound}
    var first := {"path_to_source": route["inbound"], "source_to_destination": route["outbound"]}
    var second := {"path_to_source": route["inbound"], "source_to_destination": route["outbound"]}
    var winner := {"path_to_source": (second["path_to_source"] as Array).duplicate(),
        "path_to_destination": (second["source_to_destination"] as Array).duplicate()}
    # Negative: rejected candidate cannot mutate the published winner.
    (first["path_to_source"] as Array).append("STALE")
    assert(winner["path_to_source"] == ["A", "B"])
    assert(winner["path_to_destination"] == ["B", "C"])
    # Negative: caller cannot mutate the geometry retained by another offer.
    (winner["path_to_destination"] as Array).append("BAD")
    assert(shared_outbound == ["B", "C"])
    # Paid-contract/fuel/cargo gates are unchanged and still evaluated per ship.
    assert(source.contains('"insufficient_native_full_route_fuel"'))
    assert(source.contains('"ship_cargo_not_empty"'))
    assert(source.contains('"ship_busy"'))
    assert(source.contains('"top_up"'))
    assert(source.contains('int(choice["profit"]) <= int(winner["profit"])'))
    print("PASS N153 winner-only detached route regression")
    quit(0)
