#!/usr/bin/env python3
"""Cheap native catalog proof, including an intentionally deadlocked energy variant."""
import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from recipe_graph_lab import parse_native_catalog,reachable_goods,proposed_energy_cells_t1,Recipe,dependency_report

class RecipeGraphTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.native=parse_native_catalog()

    def test_current_refinery_gas_only_for_polymers(self):
        ids=[r.id for r in self.native if r.facility_type=="refinery"
            and any(c=="Gas" for c,_ in r.inputs)]
        self.assertEqual(ids,["refine_polymers"])
        self.assertNotIn("crack_fuel",[r.id for r in self.native])
    def test_ice_still_starts_water_and_fuel(self):
        r=next(x for x in self.native if x.id=="process_ice")
        self.assertEqual(r.inputs,(("Ice",8),))
        self.assertEqual(dict(r.outputs),{"Water":10,"Fuel":5})
    def test_energy_cells_proposed_bootstrap_has_no_unreachable_essential(self):
        future=reachable_goods(proposed_energy_cells_t1(self.native))
        for needed in ("Fuel","EnergyCells","Metals","Polymers","Food",
                       "Components","Electronics"):
            self.assertIn(needed,future)
    def test_blocked_bootstrap_is_detectable(self):
        future=proposed_energy_cells_t1(self.native)
        broken=[]
        for r in future:
            if r.id in ("process_ice","charge_energy_cells"):
                broken.append(Recipe(r.id,r.facility_type,
                    r.inputs+(("EnergyCells",1),),r.outputs))
            else:broken.append(r)
        self.assertNotIn("EnergyCells",reachable_goods(broken),
            "Energy production must not self-depend unless an independent bootstrap exists")
    def test_real_recipe_catalog_is_not_synthetic(self):
        self.assertGreaterEqual(len(self.native),10)
        report=dependency_report()
        self.assertTrue(report["native_ice_to_fuel_recipe"])

if __name__=="__main__":
    unittest.main()
