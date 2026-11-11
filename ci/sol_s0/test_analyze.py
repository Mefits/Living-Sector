"""Unit tests for S0 anti-false-green guarantees, no Genesis process needed."""
import unittest
from analyze import assess,inventory,pressure,market,contract_match

def snapshot(tick,stock=5,commodity="water",destination="earth-station",
             status=None,quantity=None,goal=True):
    contracts=[]
    if status:
        c={"id":"real-contract-11","commodity":commodity,
           "destination_location":destination,"status":status,
           "funding":{"reserved":25}}
        if quantity is not None:c["delivered_units"]=quantity
        contracts=[c]
    return {"health":{"tick":tick},"report":{"tick":tick,"world_seed":7,
       "markets":[{"facility_location":"earth-station",
                   "supply":{"water":stock,"food":100,"fuel":100},
                   "demand":{"water":10,"food":1,"fuel":1}}],
       "facilities":[{"location":"earth-station","type":"station"}]},
       "strategy":{"factions":[{"faction_id":"genesis",
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
    def test_verified_cargo_still_does_not_prove_causal_relief(self):
        xs=[snapshot(100,status="accepted"),
            snapshot(200,stock=2,status="picked_up"),
            snapshot(300,stock=9,status="delivered",quantity=7)]
        w=assess(xs,[])["by_commodity"]["water"]
        self.assertEqual(w["contract_id"],"real-contract-11")
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
    def test_missing_delivery_amount_cannot_invent_units(self):
        xs=[snapshot(100,status="accepted"),
            snapshot(200,status="picked_up"),
            snapshot(300,stock=50,status="delivered")]
        w=assess(xs,[])["by_commodity"]["water"]
        self.assertIsNone(w["delivered_units"])
        self.assertFalse(w["delivery_verified"])
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
