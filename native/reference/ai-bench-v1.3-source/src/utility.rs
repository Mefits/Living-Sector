use cranium::actionset::ActionSet;
use cranium::bevy::prelude::*;
use cranium::considerations::{ConsiderationData, ConsiderationPlugin};
use cranium::context_fetchers::ContextFetcherPlugin;
use cranium::decision_loop::{decision_engine, prepare_ai};
use cranium::events::{AiActionPicked, NoDecisionMessage};
use cranium::prelude::*;
use cranium::smart_object::ActionSetStore;

#[derive(Resource, Default)]
struct Candidates {
    active: Vec<Entity>,
    picked: Option<Entity>,
}

#[derive(Component)]
struct Score(f32);

fn contexts(_: ContextFetcherInputs, candidates: Res<Candidates>) -> ContextFetcherOutputs {
    candidates.active.clone()
}

fn score(input: ConsiderationInputs, scores: Query<&Score>) -> ConsiderationOutputs {
    scores.get(input.0.2).ok().map(|s| s.0)
}

fn picked(event: On<AiActionPicked>, mut candidates: ResMut<Candidates>) {
    candidates.picked = Some(event.action_context);
}

pub struct Utility {
    app: App,
    actor: Entity,
    entities: Vec<Entity>,
    action_set: SmartObjects,
}
impl Utility {
    pub fn new(capacity: usize) -> Self {
        let mut app = App::new();
        // Register Cranium's decision observers directly. The bench owns
        // execution, so its optional action trackers are unnecessary.
        app.add_plugins((ContextFetcherPlugin, ConsiderationPlugin))
            .add_message::<NoDecisionMessage>()
            .init_resource::<ActionSetStore>()
            .init_resource::<Candidates>()
            .add_observer(prepare_ai)
            .add_observer(decision_engine)
            .add_observer(picked)
            .register_consideration(score, "bench_value")
            .register_context_fetcher(contexts, "bench_candidates");
        let w = app.world_mut();
        let actor = w.spawn(AIController::default()).id();
        let entities = (0..capacity).map(|_| w.spawn(Score(0.0)).id()).collect();
        let template = ActionTemplate::new(
            "bench choice",
            "bench_candidates",
            vec![ConsiderationData::new("bench_value", "Linear", 0.0, 1.0)],
            1.0,
            "bench_pick",
            None,
            None,
        );
        let name = "bench_set".to_owned();
        w.resource_mut::<ActionSetStore>().map_by_name.insert(
            name.clone(),
            ActionSet {
                name: name.clone(),
                actions: vec![template],
            },
        );
        let action_set = SmartObjects {
            actionset_refs: ThreadSafeRef::new(vec![name]),
        };
        app.finish();
        app.cleanup();
        app.update();
        Self {
            app,
            actor,
            entities,
            action_set,
        }
    }

    pub fn select(&mut self, options: &[(usize, f64)]) -> Option<usize> {
        if options.is_empty() {
            return None;
        }
        let low = options.iter().map(|x| x.1).fold(f64::INFINITY, f64::min);
        let high = options
            .iter()
            .map(|x| x.1)
            .fold(f64::NEG_INFINITY, f64::max);
        let mut active = Vec::with_capacity(options.len());
        let w = self.app.world_mut();
        for &(index, value) in options {
            let e = self.entities[index];
            // Affine rescaling preserves ordering and keeps legal choices above Cranium's zero cutoff.
            let normalized = if high > low {
                0.1 + 0.8 * (value - low) / (high - low)
            } else {
                0.5
            };
            w.get_mut::<Score>(e).unwrap().0 = normalized as f32;
            active.push(e);
        }
        *w.resource_mut::<Candidates>() = Candidates {
            active,
            picked: None,
        };
        w.trigger(AiDecisionRequested {
            entity: self.actor,
            request_key: None,
            smart_objects: Some(self.action_set.clone()),
        });
        w.flush();
        let selected = w.resource::<Candidates>().picked?;
        self.entities.iter().position(|&entity| entity == selected)
    }
}
