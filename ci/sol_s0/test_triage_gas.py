"""S1 gas triage must never label unrelated ship failures as gas blockers."""
import unittest
from triage_gas import examine

def sample(tick=100):
    return {"health":{"tick":tick},"report":{
        "facilities":[{"type":"station","location":"earth-station",
                       "faction_id":"terran-authority"}],
        "markets":[{"facility_location":"earth-station",
                    "shortage_ticks":{"gas":32},"supply":{"gas":0},
                    "demand":{"gas":8}},
                   {"facility_location":"alpha-station",
                    "supply":{"gas":200},"demand":{"gas":1}}],
        "ships":[{"id":"ship-1","faction_id":"terran-authority","current_goal":"refuel"}]},
        "strategy":{"factions":[{"faction_id":"terran-authority",
           "goals":[{"destination":"earth-station","commodity":"gas",
                     "goal_id":"supply_industry"}]}]},
        "contracts":[{"id":"contract-3","commodity":"gas",
          "faction_id":"terran-authority",
          "destination_location":"earth-station","source_location":"alpha-station",
          "status":"posted","funding":{"reserved":100}}]}

class CorrelationIsNotProof(unittest.TestCase):
    def test_unscoped_rejection_is_not_gas_specific(self):
        data=examine([sample()],[{"tick":101,"event":{
            "kind":"ship_transaction_rejected","reason":"contract_unavailable",
            "ship_id":"ship-1"}}])
        self.assertEqual(data["contract_count"],1)
        self.assertEqual(data["generic_all_ship_rejections_by_reason"],
                         {"contract_unavailable":1})
        self.assertEqual(data["rejections_directly_identifying_gas_contract"],[])
    def test_exact_contract_id_is_scoped(self):
        data=examine([sample()],[{"tick":101,"event":{
            "kind":"ship_transaction_rejected","reason":"contract_unavailable",
            "contract_id":"contract-3","ship_id":"ship-1"}}])
        self.assertEqual(len(data["rejections_directly_identifying_gas_contract"]),1)
    def test_other_faction_contract_does_not_count(self):
        s=sample()
        s["contracts"][0]["faction_id"]="pirates"
        self.assertEqual(examine([s],[])["contract_count"],0)

if __name__=="__main__":unittest.main()
