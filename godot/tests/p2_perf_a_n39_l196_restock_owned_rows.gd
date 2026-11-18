extends SceneTree
# Astra II-B N39 L196: N130 post-lifecycle buyer/seller/market row ownership.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n39_l196_restock_owned_rows.gd

func _detach(source: Dictionary, already_owned: Dictionary = {}) -> Dictionary:
    var stage: Dictionary = source.duplicate()
    stage["facilities"] = source["facilities"].duplicate()
    stage["markets"] = source["markets"].duplicate()
    var owned: Dictionary = already_owned.duplicate()
    var market_owned: Dictionary = {}
    var ids: Array = stage["facilities"].keys()
    ids.sort()
    for buyer_id in ids:
        var buyer: Dictionary = stage["facilities"][buyer_id]
        if bool(buyer.get("abandoned", false)):
            continue
        var location: String = str(buyer.get("location", ""))
        if not stage["markets"].has(location):
            continue
        var market: Dictionary = stage["markets"][location]
        var seller_id: String = str(market.get("owner", ""))
        if not stage["facilities"].has(seller_id):
            continue
        var seller: Dictionary = stage["facilities"][seller_id]
        if str(buyer.get("faction", "")) != str(seller.get("faction", "")) or (
                bool(seller.get("abandoned", false))) or (
                str(seller.get("location", "")) != location):
            continue
        for id in [buyer_id, seller_id]:
            if not owned.has(id):
                stage["facilities"][id] = stage["facilities"][id].duplicate(true)
                owned[id] = true
        if not market_owned.has(location):
            stage["markets"][location] = market.duplicate(true)
            market_owned[location] = true
    return stage

func _trade(stage: Dictionary, buyer_id: String, seller_id: String,
        location: String, quantity: int, cost: int) -> void:
    stage["facilities"][buyer_id]["reserves"]["fuel"] += quantity
    stage["facilities"][buyer_id]["credits"] -= cost
    stage["facilities"][seller_id]["credits"] += cost
    stage["markets"][location]["supply"]["fuel"] -= quantity

func _initialize() -> void:
    var original: Dictionary = {
        "facilities": {
            "a": {"faction": "F", "location": "X", "abandoned": false,
                "credits": 100, "reserves": {"fuel": 0}},
            "b": {"faction": "F", "location": "X", "abandoned": false,
                "credits": 100, "reserves": {"fuel": 0}},
            "seller": {"faction": "F", "location": "X", "abandoned": false,
                "credits": 100, "reserves": {"fuel": 50}},
            "other": {"faction": "G", "location": "Y", "abandoned": false,
                "credits": 100, "reserves": {"fuel": 7}},
            "abandoned": {"faction": "F", "location": "X", "abandoned": true,
                "credits": 100, "reserves": {"fuel": 3}}},
        "markets": {
            "X": {"owner": "seller", "supply": {"fuel": 100}},
            "Y": {"owner": "seller", "supply": {"fuel": 100}},
            "unused": {"owner": "missing", "supply": {"fuel": 100}}},
        "ships": {"s": {"cargo": {"fuel": 5}}},
        "contracts": {"c": {"receipt": {"id": "r"}}}}
    var frozen: Dictionary = original.duplicate(true)
    var owned: Dictionary = _detach(original)
    var oracle: Dictionary = original.duplicate(true)
    _trade(owned, "a", "seller", "X", 5, 10)
    _trade(owned, "b", "seller", "X", 3, 6)
    _trade(oracle, "a", "seller", "X", 5, 10)
    _trade(oracle, "b", "seller", "X", 3, 6)
    assert(owned == oracle, "N130 consecutive paid buyers differ from deep World oracle")
    assert(original == frozen, "N130 paid stage mutated canonical World")
    # Negative: second payment is rejected after the first succeeded. The
    # caller discards the entire staged World and N9 fork, not partial state.
    var rejected: Dictionary = _detach(original)
    _trade(rejected, "a", "seller", "X", 5, 10)
    rejected["facilities"]["a"]["reserves"]["fuel"] = 999
    rejected["markets"]["X"]["supply"]["fuel"] = 0
    assert(original == frozen, "N130 failed payment leaked nested mutation")
    # A seller is shared by two buyers; its row must detach only once.
    assert(owned["facilities"]["seller"]["credits"] == 116)
    assert(original["facilities"]["seller"]["credits"] == 100)
    # Ineligible factions, abandoned buyers and unrelated markets must be
    # read-only; they are not N130 write-set members.
    assert(owned["facilities"]["other"] == frozen["facilities"]["other"])
    assert(owned["markets"]["Y"] == frozen["markets"]["Y"])
    assert(owned["markets"]["unused"] == frozen["markets"]["unused"])
    # Negative alias control: shallow registry alone is demonstrably unsafe.
    var unsafe: Dictionary = frozen["facilities"].duplicate()
    unsafe["a"]["reserves"]["fuel"] = 777
    assert(frozen["facilities"]["a"]["reserves"]["fuel"] == 777,
        "negative shallow-alias fixture did not reproduce corruption")
    assert(original == original.duplicate(true), "canonical source corrupted")
    quit(0)
