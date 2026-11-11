//! Conservative production dependency preview from *native Genesis* recipes.
 //! A production bill, NOT an order: no capacity, market transport, research, wages
 //! or authorization are assumed. Both station AI and head can reuse the same graph.
 use crate::economy::{commodities::Commodity, recipes};
 use serde::Serialize;
 use std::collections::HashMap;
 
 #[derive(Clone, Debug, Serialize, PartialEq, Eq)]
 pub struct RecipeStep {
     pub recipe_id: &'static str,
     pub facility_type: &'static str,
     pub batches: u32,
 }
 
 #[derive(Clone, Debug, Serialize)]
 pub struct DependencyPreview {
     pub requested: Vec<(Commodity, u64)>,
     /// Deterministic sequence in which inputs become available.
     pub steps: Vec<RecipeStep>,
     /// Surplus from by-products is retained, rather than discarded.
     pub leftover_stock: Vec<(Commodity, u64)>,
 }
 
 #[derive(Clone, Debug, Serialize, PartialEq, Eq)]
 pub enum Blocker {
     NoRecipeOrStock { commodity: Commodity, missing_units: u64 },
     Cycle { commodity: Commodity },
     ArithmeticOverflow,
 }
 
 /// One shift of the *actual producer recipe*. This is an observation
 /// of local inputs, NOT proof a factory is built, staffed, powered, or
 /// profitable; missing goods may arrive through native logistics.
 #[derive(Clone, Debug, Serialize, PartialEq, Eq)]
 pub struct InputGap {
     pub commodity: Commodity,
     pub required: u64,
     pub available: u64,
     pub missing: u64,
 }
 
 #[derive(Clone, Debug, Serialize, PartialEq, Eq)]
 pub struct LocalInputReadiness {
     pub recipe_id: &'static str,
     pub facility_type: &'static str,
     pub ready_for_one_batch: bool,
     pub inputs: Vec<InputGap>,
 }
 
 /// Inspect an actual native producer recipe for one batch at one station.
 /// A refinery with multiple valid recipes uses the least-missing recipe,
 /// ties broken by stable recipe ID. No virtual upstream production is assumed.
 pub fn local_inputs_for_one_batch(
     product: Commodity, facility_type: &str, stock: &HashMap<Commodity,u64>
 ) -> Option<LocalInputReadiness> {
     recipes::RECIPES.iter()
         .filter(|r|r.facility_type==facility_type &&
             r.outputs.iter().any(|(c,n)|*c==product && *n>0))
         .map(|r|{
             let inputs=r.inputs.iter().map(|&(commodity,qty)|{
                 let required=u64::from(qty);
                 let available=stock.get(&commodity).copied().unwrap_or(0);
                 InputGap{commodity,required,available,missing:required.saturating_sub(available)}
             }).collect::<Vec<_>>();
             LocalInputReadiness{recipe_id:r.id,facility_type:r.facility_type,
                 ready_for_one_batch:inputs.iter().all(|v|v.missing==0),inputs}
         })
         .min_by(|a,b|{
             let total=|v:&LocalInputReadiness|v.inputs.iter().map(|g|g.missing).sum::<u64>();
             total(a).cmp(&total(b)).then_with(||a.recipe_id.cmp(b.recipe_id))
         })
 }
 
 /// Build a conservative ingredient plan for multiple demanded outputs.
 ///
 /// Invariant: each raw good must already exist in the supplied local stocks.
 /// This function NEVER credits output to actual game markets or creates jobs.
 /// Input quantities use integral units, which round down native fractional stock.
 pub fn ingredients(
     requested: &[(Commodity, u64)],
     stock: &HashMap<Commodity, u64>,
 ) -> Result<DependencyPreview, Blocker> {
     let mut inventory = stock.clone();
     let mut steps = Vec::new();
     for &(commodity, amount) in requested {
         consume_or_produce(commodity, amount, &mut inventory, &mut steps, &[])?;
     }
     let mut leftover_stock: Vec<_> = inventory.into_iter().collect();
     leftover_stock.sort_by_key(|(commodity, _)| commodity.as_str());
     Ok(DependencyPreview {
         requested: requested.to_vec(),
         steps,
         leftover_stock,
     })
 }
 
 fn consume_or_produce(
     commodity: Commodity,
     amount: u64,
     inventory: &mut HashMap<Commodity, u64>,
     steps: &mut Vec<RecipeStep>,
     active: &[Commodity],
 ) -> Result<(), Blocker> {
     if amount == 0 { return Ok(()); }
     let have = *inventory.get(&commodity).unwrap_or(&0);
     if have >= amount {
         inventory.insert(commodity, have - amount);
         return Ok(());
     }
     if active.contains(&commodity) {
         return Err(Blocker::Cycle { commodity });
     }
 
     let mut blocker = Blocker::NoRecipeOrStock {
         commodity, missing_units: amount - have,
     };
     // Try alternative native recipes (ice -> fuel OR gas -> fuel) without
     // committing failed attempts. This is feasibility, not cost optimisation.
     for recipe in recipes::RECIPES {
         let Some(&(_, output_per_batch)) = recipe.outputs.iter()
             .find(|(out, _)| *out == commodity)
         else { continue };
         if output_per_batch == 0 { continue; }
         let missing = amount - have;
         let unit = u64::from(output_per_batch);
         let batches = (missing - 1) / unit + 1;
         if batches > u64::from(u32::MAX) {
             blocker = Blocker::ArithmeticOverflow;
             continue;
         }
         let mut attempt_stock = inventory.clone();
         let mut attempt_steps = steps.clone();
         let mut path = active.to_vec();
         path.push(commodity);
         let mut success = true;
         for &(input, per_batch) in recipe.inputs {
             let Some(input_qty) = u64::from(per_batch).checked_mul(batches) else {
                 blocker = Blocker::ArithmeticOverflow;
                 success = false; break;
             };
             if let Err(reason) = consume_or_produce(
                 input, input_qty, &mut attempt_stock, &mut attempt_steps, &path
             ) {
                 blocker = reason;
                 success = false;
                 break;
             }
         }
         if !success { continue; }
         for &(output, per_batch) in recipe.outputs {
             let Some(add) = u64::from(per_batch).checked_mul(batches) else {
                 blocker = Blocker::ArithmeticOverflow;
                 success = false; break;
             };
             let Some(total) = attempt_stock.get(&output)
                 .copied().unwrap_or(0).checked_add(add)
             else {
                 blocker = Blocker::ArithmeticOverflow;
                 success = false; break;
             };
             attempt_stock.insert(output, total);
         }
         if !success { continue; }
         let total = *attempt_stock.get(&commodity).unwrap_or(&0);
         if total < amount { continue; }
         attempt_stock.insert(commodity, total - amount);
         attempt_steps.push(RecipeStep {
             recipe_id: recipe.id, facility_type: recipe.facility_type,
             batches: batches as u32,
         });
         *inventory = attempt_stock;
         *steps = attempt_steps;
         return Ok(());
     }
     Err(blocker)
 }
 
 #[cfg(test)]
 mod tests {
     use super::*;
 
     #[test]
     fn real_t1_chain_from_raw_inputs_to_electronics() {
         let stock = HashMap::from([
             (Commodity::Ore, 10), (Commodity::Ice, 8), (Commodity::Gas, 6)
         ]);
         let p = ingredients(&[(Commodity::Electronics, 3)], &stock).unwrap();
         let names: Vec<_> = p.steps.iter().map(|x| x.recipe_id).collect();
         assert_eq!(names, [
             "process_ice", "smelt_metals", "refine_polymers",
             "assemble_components", "build_electronics"
         ]);
         assert_eq!(p.leftover_stock.iter().find(|(c,_)| *c == Commodity::Ore).unwrap().1, 0);
         assert_eq!(stock[&Commodity::Ore], 10, "planning must not mutate game stocks");
     }
 
     #[test]
     fn use_alternative_fuel_source_if_ice_is_missing() {
         let stock = HashMap::from([(Commodity::Gas, 6)]);
         let p = ingredients(&[(Commodity::Fuel, 4)], &stock).unwrap();
         assert_eq!(p.steps[0].recipe_id, "crack_fuel");
     }
 
     #[test]
     fn missing_raw_input_is_reported_without_creating_resources() {
         let stock = HashMap::from([(Commodity::Ore, 9)]);
         assert!(ingredients(&[(Commodity::Electronics, 3)], &stock).is_err());
         assert_eq!(stock[&Commodity::Ore], 9);
     }
 
     #[test]
     fn shared_byproducts_are_available_to_the_next_request() {
         let stock = HashMap::from([(Commodity::Ice, 8)]);
         let p = ingredients(&[(Commodity::Fuel, 1), (Commodity::Water, 10)], &stock).unwrap();
         assert_eq!(p.steps.len(), 1, "ice processing produces both water and fuel");
         assert_eq!(p.steps[0].recipe_id, "process_ice");
     }
 
     #[test]
     fn galaxy065_direct_recipe_inputs_are_real_not_virtual() {
         let stock=HashMap::from([(Commodity::Water,2)]);
         let p=local_inputs_for_one_batch(Commodity::Food,"farm",&stock).unwrap();
         assert_eq!(p.recipe_id,"grow_food");
         assert!(!p.ready_for_one_batch);
         assert_eq!(p.inputs[0],InputGap{commodity:Commodity::Water,
             required:3,available:2,missing:1});
         let ready=local_inputs_for_one_batch(Commodity::Food,"farm",
             &HashMap::from([(Commodity::Water,3)])).unwrap();
         assert!(ready.ready_for_one_batch);
         assert!(local_inputs_for_one_batch(Commodity::Food,"qfab3",&stock).is_none());
         assert_eq!(stock[&Commodity::Water],2,"forecast never mutates native inventory");
     }
     #[test]
     fn galaxy065_producer_recipe_checks_local_inputs_only() {
         let raw=HashMap::from([(Commodity::Ore,10),(Commodity::Fuel,1)]);
         let metal=local_inputs_for_one_batch(Commodity::Metals,"refinery",&raw).unwrap();
         assert_eq!(metal.recipe_id,"smelt_metals");
         assert!(metal.ready_for_one_batch);
         let missing=local_inputs_for_one_batch(Commodity::Electronics,"factory",&raw).unwrap();
         assert!(!missing.ready_for_one_batch);
         assert!(missing.inputs.iter().any(|g|g.commodity==Commodity::Components&&g.missing==2));
         // Constructing a factory does not magically smelt ore or spawn its inputs.
         assert_eq!(raw[&Commodity::Ore],10);
     }
 
     #[test]
     fn zero_demand_does_not_create_work() {
         assert!(ingredients(&[(Commodity::Food, 0)], &HashMap::new()).unwrap().steps.is_empty());
     }
 }
 