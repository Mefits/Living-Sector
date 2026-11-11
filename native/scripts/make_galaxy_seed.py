"""Reproducible starting endowment. No runtime grants or fabricated outcomes."""
import json,shutil
from pathlib import Path
root=Path(__file__).resolve().parents[1]
out=root/'priv/galaxy/data'
shutil.copytree(root/'priv/genesis/data',out,dirs_exist_ok=True)
factions=json.loads((out/'factions.json').read_text())
mixes=[{'economist':.6,'pacifist':.4},{'aggressor':.45,'expansionist':.55},{'technocrat':.65,'isolationist':.35}]
for f,mix in zip(factions,mixes):
 f['treasury']=240000
 f['personality']['prefer_goals'].update({'leader_'+k:v for k,v in mix.items()})
(out/'factions.json').write_text(json.dumps(factions,ensure_ascii=False,indent=2))
for path in (out/'worlds').glob('*.json'):
 d=json.loads(path.read_text())
 for body in d['bodies']:
  # Slower physical orbits let freighters rendezvous with distant bodies.
  body['orbit_period']=max(body['orbit_period'],int(body['orbit_radius']*350))
 homes=[f for f in d.get('facilities',[]) if f['type']=='station']
 for home in homes:
  owner=home['faction_id'];loc=home['location'];home['name']=next(f['name'] for f in factions if f['id']==owner)+' · Столица'
  home['services']=['market','repair','refuel']
  for f in d['facilities']:
   if f['location']==loc:
    if owner=='pirates':f['body']='callisto'
    f['credits']=60000;f['name']=f['name'].replace('Primitive','').replace('(preview)','').strip()
  body=home['body']
  d['facilities'].append(dict(id='facility-'+loc+'-factory',name='Промышленный комплекс',faction_id=owner,location=loc,body=body,type='factory',docking_capacity=2,services=[],reserves={},credits=60000))
  for m in d['markets']:
   if m['facility_id']==loc:
    m['supply']={r:600 for r in m['prices']};m['supply'].update(food=1000,water=1000,metals=1000,fuel=1000)
  for p in d['populations']:
   if p['facility_id']==loc:p.update(population_count=200,total_wealth=60000)
  d['ships']=[s for s in d['ships'] if s['faction_id']!=owner]
  for n,kind in enumerate(['miner','freighter','freighter','courier','hauler','tanker','colonizer','colonizer']):
   d['ships'].append(dict(name=f'{owner} {kind} {n+1}',location=loc,**{'class':kind},credits=40000,faction_id=owner,fitting={'comms':'comms_t2'}))
 path.write_text(json.dumps(d,ensure_ascii=False,indent=2))
