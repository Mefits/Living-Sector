"""Unit checks for the unattended economic *observer*, not the game.

Synthetic objects intentionally use the same field names as the native
Rust /api/report, /api/contracts and /api/strategy snapshots.  These tests
stop a broken dashboard from declaring the economy healthy or silently
miscounting the fourth factory.
"""
import tempfile
from pathlib import Path
import unittest

from autonomous_bench import detail, economic_warnings, emit_markdown, metrics, status_counts

def fixture():
    report={
        "tick":18448,"world_seed":12345,
        "ships":[
            {"id":"ship-rich","credits":250_000,"current_goal":"trade_run","fuel":80},
            {"id":"ship-stuck","credits":75_000,"current_goal":"refuel","fuel":0},
        ],
        "factions":[
            {"id":"genesis","treasury":2_000},
            {"id":"pirates","treasury":4_000}
        ],
        "facilities":[
            {"type":"station","id":"venus-core","location":"venus-colony",
             "faction_id":"genesis","credits":100},
            *[{"type":t,"location":"venus-colony","faction_id":"genesis",
               "credits":20} for t in ("farm","mining_rig","refinery")],
        ],
        "construction_sites":[
            {"id":"site-factory","location":"venus-colony","faction_id":"genesis",
             "facility_type":"factory","progress_delivered":400,
             "progress_required":600,"labor":{"required":150,"completed":0,
             "blocked_reason":"awaiting_materials"}}
        ],
        "populations":[
            {"id":"pop-venus","facility_location":"venus-colony",
             "food_satisfaction":0,"total_wealth":0,"population_count":50},
            {"id":"pop-earth","facility_location":"earth-station",
             "food_satisfaction":100,"total_wealth":3_000,"population_count":500}
        ],
        "markets":[
            {"id":"m-venus","facility_location":"venus-colony",
             "supply":{"food":0,"water":15,"fuel":3}}
        ]
    }
    contracts=[
        {"id":"paid-food","commodity":"food","status":"paid"},
        {"id":"open-food","commodity":"food","status":"posted"},
        {"id":"expired-food","commodity":"food","status":"expired"},
        {"id":"paid-water","commodity":"water","status":"paid"},
        {"id":"paid-metals","commodity":"metals","status":"paid"}
    ]
    strategy={
        "orders":[{"state":"waiting","blocked_reason":"carrier_missing"},
                  {"state":"completed","blocked_reason":None}],
        "colonies":[{"faction_id":"genesis","location":"venus-colony",
                      "phase":"life_support","reason":"colony_food_shortage"}],
    }
    events={
        "event_types":{"ship_operating_levy":8,"ship_transaction_rejected":25},
        "rejections_by_reason":{"no_fuel_transfer":22,"invalid_destination_stock":3},
        "websocket_connected_at_least_once":True
    }
    return report,contracts,strategy,events

class BenchAnalysisTests(unittest.TestCase):
    def test_real_api_schema_counts_money_and_colonies(self):
        report,contracts,strategy,events=fixture()
        m=metrics(report,contracts,events,10.5)
        self.assertEqual(m["tick"],18448)
        self.assertEqual(m["world_seed"],12345)
        self.assertEqual(m["ships"],2)
        self.assertEqual(m["stations"],1)
        self.assertEqual(m["colonies"],1)
        self.assertEqual(m["ship_credits"],325_000)
        self.assertEqual(m["faction_treasuries"],6_000)
        self.assertEqual(m["facility_credits"],160)
        self.assertEqual(m["household_credits"],3_000)
        self.assertEqual(m["starving_colonies"],1)
        self.assertEqual(m["colonies_without_food_stock"],1)
        self.assertEqual(m["colonies_without_water_stock"],0)
        self.assertEqual(m["zero_credit_colonies"],1)
        self.assertEqual(m["paid_food_contracts"],1)
        self.assertEqual(m["paid_water_contracts"],1)
        self.assertEqual(m["paid_metals_contracts"],1)
        self.assertEqual(m["expired_contracts"],1)
        self.assertEqual(m["active_contracts"],1)
        self.assertEqual(m["stranded_refuel_ships"],1)
        self.assertEqual(m["fleet_levy_events"],8)
        self.assertEqual(m["rejected_ship_transactions"],25)
        self.assertEqual(status_counts(contracts,"food"),
                         {"expired":1,"paid":1,"posted":1})

    def test_fourth_factory_is_a_real_construction_site_not_built(self):
        report,contracts,strategy,events=fixture()
        d=detail(report,contracts,strategy)
        colony=d["colonies"][0]
        self.assertEqual(colony["food_stock"],0)
        self.assertEqual(colony["water_stock"],15)
        self.assertEqual(colony["population"],50)
        station=d["station_buildings"][0]
        self.assertEqual(station["built_count"],3)
        self.assertEqual(station["construction_count"],1)
        self.assertEqual(station["visual_t1_occupancy"],4)
        self.assertEqual(station["projects"],["factory"])
        self.assertEqual(d["construction_sites"][0]["delivered"],400)
        self.assertEqual(d["construction_sites"][0]["required"],600)
        self.assertEqual(d["construction_sites"][0]["reason"],"awaiting_materials")
        self.assertEqual(d["station_order_blocks"],{"carrier_missing":1})

    def test_warning_engine_keeps_runtime_separate_from_economic_health(self):
        report,contracts,strategy,events=fixture()
        m=metrics(report,contracts,events,10)
        d=detail(report,contracts,strategy)
        cp={"metrics":m,"detail":d,"events":events}
        warnings=economic_warnings([cp,cp])
        self.assertTrue(any("food" in w for w in warnings))
        self.assertTrue(any("household" in w for w in warnings))
        self.assertTrue(any("liquidity trap" in w for w in warnings))
        self.assertTrue(any("Construction" in w for w in warnings))
        self.assertTrue(any("no_fuel_transfer" in w for w in warnings))
        self.assertTrue(any("paid food contracts" in w for w in warnings))

    def test_report_is_written_even_if_runtime_fails(self):
        report,contracts,strategy,events=fixture()
        m=metrics(report,contracts,events,0)
        s={"status":"failed_runtime","build_sha":"123abc",
           "started_utc":"2026-11-11T00:00:00Z","finished_utc":"2026-11-11T00:10:00Z",
           "checkpoints":[{"metrics":m}],"warnings":["economy not assessed"]}
        with tempfile.TemporaryDirectory() as p:
            target=Path(p)/"REPORT-RU.md"
            emit_markdown(s,target)
            txt=target.read_text(encoding="utf8")
            self.assertIn("failed_runtime",txt)
            self.assertIn("18448",txt)
            self.assertIn("economy not assessed",txt)

if __name__=="__main__":
    unittest.main()
