#!/usr/bin/env python3
import unittest
from audit_operations import analyze

CID="contract-earth-gas"
SHIP="ship-terran-hauler"

def tx(t,op,cid=CID,ship=SHIP,kind="ship_transaction_applied",
       loc=None,commodity=None,qty=None):
    return {"tick":t,"event":{"kind":kind,"operation":op,
        "contract_id":cid,"ship_id":ship,"location":loc,
        "commodity":commodity,"quantity":qty}}

def receipt(t,cid=CID):
    return {"tick":t,"event":{"kind":"contract_delivered",
        "contract_id":cid,"contract_type":"delivery",
        "commodity":"gas","destination":"earth-station"}}

def chain():
    return [tx(5,"accept"),tx(8,"buy",loc="alpha-station",commodity="gas",qty=200),
            tx(36,"deliver"),receipt(36)]

class StrictOperationChain(unittest.TestCase):
    def test_real_accept_buy_deliver_receipt_on_exact_ship_and_contract(self):
        a=analyze(chain())
        self.assertEqual(a["complete_market_gas_chains"],1)
        detail=a["gas_market_receipts"][0]["matched_chain"]
        self.assertEqual(detail["ship_id"],SHIP)
        self.assertEqual(detail["buy_units"],200)

    def test_paid_or_receipt_without_buy_never_proves_three_steps(self):
        a=analyze([tx(5,"accept"),tx(36,"deliver"),receipt(36)])
        self.assertEqual(a["complete_market_gas_chains"],0)
        self.assertEqual(len(a["gas_market_receipts"]),1)

    def test_buy_for_another_contract_is_not_matching(self):
        x=chain()
        x[1]["event"]["contract_id"]="unrelated"
        self.assertEqual(analyze(x)["complete_market_gas_chains"],0)

    def test_wrong_ship_cannot_reuse_someone_elses_purchase(self):
        x=chain()
        x[1]["event"]["ship_id"]="another-ship"
        self.assertEqual(analyze(x)["complete_market_gas_chains"],0)

    def test_rejected_buy_is_not_a_purchase(self):
        x=chain()
        x[1]["event"]["kind"]="ship_transaction_rejected"
        self.assertEqual(analyze(x)["complete_market_gas_chains"],0)
        self.assertEqual(a:=analyze(x)["generic_rejections_NOT_CAUSALLY_LINKED"].get("missing_reason"),1)

    def test_wrong_location_and_commodity_is_not_source_purchase(self):
        for key,value in (("location","earth-station"),("commodity","metals")):
            with self.subTest(key=key):
                x=chain()
                x[1]["event"][key]=value
                self.assertEqual(analyze(x)["complete_market_gas_chains"],0)

    def test_chronology_must_be_native(self):
        x=chain()
        x[1]["tick"]=39
        self.assertEqual(analyze(x)["complete_market_gas_chains"],0)

    def test_unrelated_receipts_do_not_count(self):
        x=chain()
        x[-1]["event"]["destination"]="alpha-station"
        self.assertEqual(analyze(x)["complete_market_gas_chains"],0)

if __name__=="__main__":unittest.main()
