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
    # Real N111 ready construction produces a LIVE competitor score
    # 35*industry + 8 (site present). 60-point native migration needs
    # two distinct strategic decision cycles to overcome 43 by 1.20.
    var competing: Dictionary = _world()
    competing["research_directors"]["terran-authority"]["profile"] = {
        "industry": 1.0, "science": 1.0, "expansion": 1.0}
    competing["research_directors"]["terran-authority"]["strategic"] = {
        "kind": "supply",
        "target": "develop_colony|earth-station|metals",
        "score": 43.0, "since": 10, "reason": "viable_commitment_retained",
        "pending": null}
    var build: Dictionary = _head()
    build["selected_option"] = "build"
    build["selected_administrator"] = "construction"
    build["problem"] = {"goal_id": "develop_colony",
        "destination": "earth-station", "commodity": "metals",
        "shortage_ticks": 0}
    build["alternatives"] = [{"action": "build", "status": "ready",
        "site_id": "original-n154-site", "covered_units": 1.0,
        "estimated_net_value": 0.0}]
    var source_copy: Dictionary = competing.duplicate(true)
    var first_cycle: Dictionary = HeadGrant.authorize(
        competing, "terran-authority", _ready(), build, 60)
    if not first_cycle.get("ok", false) or first_cycle.get(
            "authorized", true) or not first_cycle.get(
            "pending", false) or str(first_cycle.get(
            "reason", "")) != "alternative_pending_confirmation" or (
            competing != source_copy):
        _fail("live N111 build lost source N113 first-cycle pending vote")
        return
    var repeat_cycle: Dictionary = HeadGrant.authorize(
        {"faction_treasuries": competing["faction_treasuries"],
        "research_directors": {"terran-authority": {
            "profile": competing["research_directors"][
                "terran-authority"]["profile"],
            "strategic": first_cycle["strategy"]}},
        "native_execution": {"active": {}},
        "native_planner_records": {}, "contract_board": {"contracts": {}}},
        "terran-authority", _ready(), build, 60)
    if repeat_cycle.get("ok", true):
        _fail("one native strategic tick counted twice")
        return
    competing["research_directors"]["terran-authority"][
        "strategic"] = first_cycle["strategy"].duplicate(true)
    build["observed_tick"] = 120
    var second_cycle: Dictionary = HeadGrant.authorize(
        competing, "terran-authority", _ready(), build, 120)
    if not second_cycle.get("ok", false) or not second_cycle.get(
            "authorized", false) or str(second_cycle.get(
            "reason", "")) != "sustained_higher_utility" or (
            second_cycle["head"]["selected_option"] != "migrate_colony"):
        _fail("real N113 1.2x two-cycle migration never received Head grant")
        return
    var recovered: Dictionary = competing.duplicate(true)
    recovered["research_directors"]["terran-authority"]["profile"][
        "industry"] = 2.0
    # The real N111 incumbent capability score is now 78 > 60.
    var reset_cycle: Dictionary = HeadGrant.authorize(
        recovered, "terran-authority", _ready(), build, 120)
    if not reset_cycle.get("ok", false) or reset_cycle.get(
            "authorized", true) or reset_cycle["strategy"][
            "pending"] != null:
        _fail("stale migration pending overrode newly stronger real N111 build")
        return
    var wrong_faction: Dictionary = _ready()
    wrong_faction["faction_id"] = "ceti-freeholds"
    if HeadGrant.authorize(source, "terran-authority",
            wrong_faction, _head(), 60).get("ok", true):
        _fail("wrong N104 owner got faction authority")
        return
    print("P2_B4_N147_SOURCE_HEAD_GRANT_CHECK_PASS")
    quit(0)
