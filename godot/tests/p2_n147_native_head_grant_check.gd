extends SceneTree
## Deferred original Rust N92/N147 -> one N134 Head -> N104/N9 gate.
## Source-only acceptance, not a Game/F5/CI runtime PASS.
const HeadGrant = preload("res://scripts/sim/phase2/unified_n147_colony_head_grant.gd")

func _fail(message: String) -> void:
    push_error("P2_CHAT2_B4_TAKEOVER_N147: " + message)
    quit(1)

func _world() -> Dictionary:
    return {
        "faction_treasuries": {"terran-authority": 40000},
        "research_directors": {"terran-authority": {
            "strategic": {"kind": "", "target": "", "score": 0.0,
                "since": 0, "reason": "", "pending": null}}},
        "native_execution": {"active": {}},
        "native_planner_records": {},
        "contract_board": {"contracts": {}}}

func _ready() -> Dictionary:
    return {"faction_id": "terran-authority",
        "source": "earth-station", "destination": "mars-colony",
        "quantity": 10, "payment": 800,
        "status": "N147_PREPARED_NOT_POSTED"}

func _head() -> Dictionary:
    return {"observed_tick": 60, "selected_option": "wait",
        "selected_administrator": "",
        "reason": "wait_no_positive_option", "planned_spend": 0,
        "problem": {}}

func _initialize() -> void:
    var source: Dictionary = _world()
    var before: Dictionary = source.duplicate(true)
    var grant: Dictionary = HeadGrant.authorize(
        source, "terran-authority", _ready(), _head(), 60)
    if not grant.get("ok", false) or not grant.get(
            "authorized", false) or str(grant.get("head", {}).get(
            "selected_option", "")) != "migrate_colony":
        _fail("real free original N134 Head did not grant source N92 migration")
        return
    if grant["strategy"]["kind"] != "migrate" or grant[
            "strategy"]["target"] != "mars-colony" or int(grant[
            "head"]["planned_spend"]) != 800:
        _fail("original N113 memory/Head and physical funding terms diverged")
        return
    if source != before or int(source[
            "faction_treasuries"]["terran-authority"]) != 40000:
        _fail("pure Head grant minted a contract, cash, people or memory")
        return
    var busy: Dictionary = _head()
    busy["selected_option"] = "build"
    busy["selected_administrator"] = "construction"
    if HeadGrant.authorize(source, "terran-authority",
            _ready(), busy, 60).get("authorized", true):
        _fail("active paid construction Head was displaced by passengers")
        return
    busy = _head()
    busy["reason"] = "already_commissioned_this_tick"
    if HeadGrant.authorize(source, "terran-authority",
            _ready(), busy, 60).get("authorized", true):
        _fail("already commissioned N134 Head posted another funded order")
        return
    var stale: Dictionary = _head()
    stale["observed_tick"] = 59
    if HeadGrant.authorize(source, "terran-authority",
            _ready(), stale, 60).get("ok", true):
        _fail("previous cycle Head authorized new passenger debit")
        return
    var another: Dictionary = _world()
    another["native_execution"]["active"]["terran-authority"] = {
        "plan_id": "real-N98-paid-freight"}
    if HeadGrant.authorize(another, "terran-authority",
            _ready(), _head(), 60).get("authorized", true):
        _fail("existing paid N98/N121 plan was preempted")
        return
    another = _world()
    another["contract_board"]["contracts"]["already-paid"] = {
        "requestor_id": "faction/terran-authority",
        "status": "accepted", "posted_at_tick": 60,
        "mission_category": "strategy.colony.v1"}
    if HeadGrant.authorize(another, "terran-authority",
            _ready(), _head(), 60).get("authorized", true):
        _fail("faction received two original Head-paid grants same tick")
        return
    another = _world()
    another["research_directors"]["terran-authority"]["crisis"] = true
    if HeadGrant.authorize(another, "terran-authority",
            _ready(), _head(), 60).get("authorized", true):
        _fail("original survival crisis wrongly approved workforce migration")
        return
    another = _world()
    another["research_directors"]["terran-authority"]["strategic"][
        "kind"] = "supply"
    another["research_directors"]["terran-authority"]["strategic"][
        "target"] = "earth-station|food"
    if HeadGrant.authorize(another, "terran-authority",
            _ready(), _head(), 60).get("authorized", true):
        _fail("retained source supply commitment was replaced without N113 vote")
        return
    another = _world()
    another["research_directors"]["terran-authority"]["strategic"][
        "kind"] = "migrate"
    another["research_directors"]["terran-authority"]["strategic"][
        "target"] = "mars-colony"
    another["research_directors"]["terran-authority"]["strategic"][
        "since"] = 30
    var retained: Dictionary = HeadGrant.authorize(
        another, "terran-authority", _ready(), _head(), 60)
    if not retained.get("authorized", false) or int(retained[
            "strategy"]["since"]) != 30:
        _fail("existing source migration strategic commitment not retained")
        return
    var wrong_faction: Dictionary = _ready()
    wrong_faction["faction_id"] = "ceti-freeholds"
    if HeadGrant.authorize(source, "terran-authority",
            wrong_faction, _head(), 60).get("ok", true):
        _fail("wrong N104 owner got faction authority")
        return
    print("P2_B4_N147_SOURCE_HEAD_GRANT_CHECK_PASS")
    quit(0)
