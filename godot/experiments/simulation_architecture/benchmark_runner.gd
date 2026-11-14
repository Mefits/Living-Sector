extends RefCounted
## Three scheduling strategies over one N73/N9 world and the same event order.
const World = preload("res://experiments/simulation_architecture/benchmark_world.gd")
const Heap = preload("res://experiments/simulation_architecture/event_heap.gd")

static func run(mode: String, plant_count: int, ship_count: int,
        ticks: int, seed: int) -> Dictionary:
    var world = World.new()
    world.initialize(plant_count, ship_count, seed)
    var checks: int = 0
    var handled: int = 0
    var peak: int = 0
    var started: int = Time.get_ticks_usec()

    if mode == "tick":
        for tick in range(1, ticks + 1):
            # Preserve arrivals -> departures -> production tie order.
            for i in range(ship_count):
                checks += 1
                if int(world.ships[i]["arrival"]) == tick:
                    world.arrive(i, tick)
            for i in range(ship_count):
                checks += 1
                if int(world.ships[i]["departure"]) == tick:
                    world.depart(i, tick)
            for i in range(plant_count):
                checks += 1
                if tick % World.CADENCE == 0:
                    world.produce(i)

    elif mode == "event":
        var queue = Heap.new()
        for i in range(ship_count):
            queue.push(int(world.ships[i]["departure"]), 1, i)
        for i in range(plant_count):
            queue.push(World.CADENCE, 2, i)
        while not queue.empty() and queue.due_time() <= ticks:
            var event: Dictionary = queue.pop()
            handled += 1
            var due: int = int(event["tick"])
            var entity: int = int(event["entity"])
            match int(event["phase"]):
                0:
                    var market_id: int = world.arrive(entity, due)
                    if market_id >= 0:
                        queue.push(int(world.ships[entity]["departure"]), 1, entity)
                1:
                    var arrival_tick: int = world.depart(entity, due)
                    if arrival_tick >= 0:
                        queue.push(arrival_tick, 0, entity)
                2:
                    world.produce(entity)
                    queue.push(due + World.CADENCE, 2, entity)
        peak = queue.peak

    elif mode == "hybrid":
        var queue = Heap.new()
        for i in range(ship_count):
            queue.push(int(world.ships[i]["departure"]), 1, i)
        var now: int = 0
        while true:
            # No producer to visit? Skip recipe-only ticks until a real
            # cargo event can wake a market. Keep absolute cadence otherwise.
            var next_production: int = ticks + 1
            if world.active_count > 0:
                next_production = (
                    int(floor(float(now) / float(World.CADENCE))) + 1
                ) * World.CADENCE
            var due: int = mini(next_production, queue.due_time())
            if due > ticks:
                break
            while not queue.empty() and queue.due_time() == due:
                var event: Dictionary = queue.pop()
                handled += 1
                var entity: int = int(event["entity"])
                if int(event["phase"]) == 0:
                    var market_id: int = world.arrive(entity, due)
                    if market_id >= 0:
                        world.wake_market(market_id)
                        queue.push(int(world.ships[entity]["departure"]), 1, entity)
                else:
                    var arrival_tick: int = world.depart(entity, due)
                    if arrival_tick >= 0:
                        queue.push(arrival_tick, 0, entity)
            # An arrival at a recipe boundary must wake facilities BEFORE
            # that same boundary's facility-order pass.
            if due % World.CADENCE == 0 and world.active_count > 0:
                for i in range(plant_count):
                    if not world.active[i]:
                        continue
                    checks += 1
                    if world.produce(i):
                        world.wake_market(int(world.facilities[i]["market"]))
                    else:
                        world.sleep(i)
            now = due
        peak = queue.peak

    else:
        return {"ok": false, "error": "unknown_mode_" + mode}

    var duration: int = Time.get_ticks_usec() - started
    var issue: String = world.audit()
    return {
        "ok": issue == "", "error": issue, "mode": mode,
        "microseconds": duration, "checks": checks,
        "events": handled, "queue_peak": peak,
        "attempts": world.attempts, "batches": world.batches,
        "arrivals": world.arrivals, "state": world.state()
    }
