"""Unit tests for S0 anti-false-green guarantees, no Genesis process needed."""
import unittest
from analyze import assess,inventory,pressure,market,contract_match

def snapshot(tick,stock=5,commodity="water",destination="earth-station",
             status=None,quantity=None,goal=True):
    contracts=[]
    if status:
        c={"id":"real-contract-11","commodity":commodity,
           "destination_location":destination,"status":status,
           "faction_id":"terran-authority",
           "quantity":200,"contract_type":"delivery",
           "funding":{"reserved":25,"source":"facility"}}
        if quantity is not None:c["delivered_units"]=quantity
        contracts=[c]
    return {"health":{"tick":tick},"report":{"tick":tick,"world_seed":7,
       "markets":[{"facility_location":"earth-station",
                   "supply":{"water":stock,"food":100,"fuel":100},
                   "demand":{"water":10,"food":1,"fuel":1}}],
       "facilities":[{"location":"earth-station","type":"station",
                      "faction_id":"terran-authority"}]},
       "strategy":{"factions":[{"faction_id":"terran-authority",
           "goals":([{"goal_id":"sustain_population",
                      "destination":"earth-station","commodity":"water",
                      "status":"ready"}] if goal else [])}]},
       "contracts":contracts}

class AntiFalseGreen(unittest.TestCase):
    def test_paid_never_means_delivered_or_relieved(self):
        x=assess([snapshot(100,status="paid"),snapshot(200,stock=20,status="paid")],[])
        w=x["by_commodity"]["water"]
        self.assertIsNone(w["t_delivered"])
        self.assertFalse(w["delivery_verified"])
        self.assertEqual(w["relief_verified"],"unknown")
        self.assertEqual(x["relief_verified"],"unknown")
    def test_actual_native_market_commit_proves_delivery_without_picked_up_state(self):
        # Genesis normal deliveries transition Accepted -> Paid directly.
        # The exact engine commit event omits quantity but atomically adds
        # the actual contract quantity to destination market inventory.
        xs=[snapshot(100,status="accepted"),snapshot(200,stock=2,status="accepted"),
            snapshot(300,stock=9,status="paid")]
        event={"tick":250,"event":{"kind":"contract_delivered",
            "contract_id":"real-contract-11","contract_type":"delivery",
            "commodity":"water","destination":"earth-station","payment":50}}
        w=assess(xs,[event])["by_commodity"]["water"]
        self.assertEqual(w["contract_id"],"real-contract-11")
        self.assertIsNone(w["t_pickup"])
        self.assertEqual(w["t_delivered"],250)
        self.assertEqual(w["delivered_units"],200)
        self.assertEqual(w["delivery_quantity_source"],"exact_native_contract_quantity_on_commit_event")
        self.assertTrue(w["delivery_verified"])
        self.assertEqual(w["relief_verified"],"unknown")
    def test_unrelated_destination_does_not_count(self):
        xs=[snapshot(100,status="picked_up",destination="Mars"),
            snapshot(200,status="delivered",destination="Mars",quantity=999)]
        w=assess(xs,[])["by_commodity"]["water"]
        self.assertIsNone(w["contract_id"])
        self.assertFalse(w["delivery_verified"])
    def test_no_market_no_assumed_zero_stock(self):
        s=snapshot(100)
        s["report"]["markets"]=[]
        w=assess([s],[])["by_commodity"]["water"]
        self.assertIsNone(w["t_pressure"])
        self.assertIsNone(w["stock_before"])
    def test_paid_without_native_event_or_contract_quantity_is_not_delivery(self):
        xs=[snapshot(100,status="accepted"),snapshot(200,status="paid")]
        row={"tick":180,"event":{"kind":"contract_delivered",
            "contract_id":"real-contract-11","contract_type":"delivery",
            "commodity":"water","destination":"earth-station"}}
        # Native contract quantity missing: never synthesize it from stock.
        for s in xs:s["contracts"][0].pop("quantity")
        w=assess(xs,[row])["by_commodity"]["water"]
        self.assertIsNone(w["delivered_units"])
        self.assertFalse(w["delivery_verified"])

    def test_unrelated_contract_event_and_wrong_market_cannot_pass(self):
        xs=[snapshot(100,status="accepted"),snapshot(200,status="paid")]
        bad=[{"tick":170,"event":{"kind":"contract_delivered",
            "contract_id":"unrelated-contract","contract_type":"delivery",
            "commodity":"water","destination":"earth-station"}},
             {"tick":180,"event":{"kind":"contract_delivered",
            "contract_id":"real-contract-11","contract_type":"delivery",
            "commodity":"water","destination":"mars"}}]
        self.assertFalse(assess(xs,bad)["by_commodity"]["water"]["delivery_verified"])

    def test_construction_delivery_does_not_add_to_market(self):
        xs=[snapshot(100,status="accepted"),snapshot(200,status="paid")]
        for s in xs:s["contracts"][0]["contract_type"]="construction"
        event={"tick":170,"event":{"kind":"contract_delivered",
            "contract_id":"real-contract-11","contract_type":"construction",
            "commodity":"water","destination":"earth-station","quantity":200}}
        self.assertFalse(assess(xs,[event])["by_commodity"]["water"]["delivery_verified"])

    def test_household_consumption_is_not_market_relief(self):
        xs=[snapshot(100,status="accepted"),snapshot(200,status="paid")]
        for s in xs:s["contracts"][0]["funding"]["source"]="population"
        event={"tick":170,"event":{"kind":"contract_delivered",
            "contract_id":"real-contract-11","contract_type":"delivery",
            "commodity":"water","destination":"earth-station"}}
        self.assertFalse(assess(xs,[event])["by_commodity"]["water"]["delivery_verified"])

    def test_native_event_cannot_override_conflicting_amount(self):
        xs=[snapshot(100,status="accepted"),snapshot(200,status="paid")]
        event={"tick":170,"event":{"kind":"contract_delivered",
            "contract_id":"real-contract-11","contract_type":"delivery",
            "commodity":"water","destination":"earth-station","quantity":999}}
        self.assertFalse(assess(xs,[event])["by_commodity"]["water"]["delivery_verified"])
    def test_real_event_inventory_not_implied_contract_receipt(self):
        s=snapshot(100)
        inv=inventory([s],[{"tick":100,"event":{
            "kind":"ship_transaction_rejected","reason":"no_stock"}}])
        self.assertEqual(inv["event_kinds"],{"ship_transaction_rejected":1})
        self.assertNotIn("delivery_receipt",inv["event_keys"])
    def test_market_pressure_is_marked_weak(self):
        o=pressure(snapshot(100)["report"],"earth-station","water")
        self.assertTrue(o["pressure"])
        self.assertEqual(o["pressure_kind"],"stock_below_market_demand")
        self.assertIsNone(o["shortage_ticks"])

if __name__=="__main__":unittest.main()
