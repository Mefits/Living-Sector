//! Networking — WS client that connects to the sim on
//! `ws://localhost:8080/ws` and pushes parsed `ServerMsg` into a
//! channel the Bevy app drains each frame.
//!
//! Bundle 1.2 scope: connect + print. No state merging yet; a later
//! bundle wires messages into World resources.

use bevy::prelude::*;
use flume::{Receiver, Sender};
use futures_util::{SinkExt, StreamExt};
use sim_protocol::ServerMsg;
use std::time::Duration;
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tracing::{debug, error, info, warn};

const WS_URL: &str = "ws://localhost:8080/ws";
const RECONNECT_DELAY: Duration = Duration::from_secs(2);

/// Bevy plugin wiring up the net layer. Spawns a tokio runtime on a
/// dedicated thread, runs the WS client there, and hands received
/// `ServerMsg`s to the Bevy side via a flume channel.
pub struct NetPlugin;

impl Plugin for NetPlugin {
    fn build(&self, app: &mut App) {
        let (tx, rx) = flume::unbounded::<ServerMsg>();
        let (out_tx, _out_rx) = mpsc::unbounded_channel::<String>();

        // Dedicated tokio runtime — Bevy runs its own scheduling on
        // the main thread, so networking lives on a separate runtime
        // and shuttles messages in via flume. The out channel is
        // reserved for Bundle 2 when we start sending MoveObserver /
        // SimControl / etc. from Bevy systems back to the server.
        std::thread::Builder::new()
            .name("client-bevy-net".into())
            .spawn(move || {
                let rt = tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                    .expect("failed to build tokio runtime");
                rt.block_on(run_net_loop(tx, _out_rx));
            })
            .expect("failed to spawn net thread");

        app.insert_resource(NetInbox(rx))
            .insert_resource(NetOutbox(out_tx))
            .add_systems(Update, drain_inbox);
    }
}

/// Bevy Resource — the Receiver side of the flume channel. Systems
/// in the Bevy app drain it each frame.
#[derive(Resource)]
pub struct NetInbox(pub Receiver<ServerMsg>);

/// Bevy Resource — send channel for ClientMsg-equivalent strings that
/// the net loop forwards to the server. Wrapping String keeps the
/// plugin oblivious to the exact ClientMsg shape during bundle 1.
#[derive(Resource)]
pub struct NetOutbox(#[allow(dead_code)] pub mpsc::UnboundedSender<String>);

/// Bundle 1.2: just log every received message so we can confirm the
/// wire is up. Bundle 2 replaces this with real state merges.
fn drain_inbox(inbox: Res<NetInbox>) {
    while let Ok(msg) = inbox.0.try_recv() {
        log_received(&msg);
    }
}

fn log_received(msg: &ServerMsg) {
    match msg {
        ServerMsg::ServerHello { tick, running, agent_count, world_speed, .. } => {
            info!(
                "server_hello: tick={} running={} agents={} world_speed={:.2}",
                tick, running, agent_count, world_speed
            );
        }
        ServerMsg::Positions { tick, entities, .. } => {
            debug!("positions: tick={} count={}", tick, entities.len());
        }
        ServerMsg::ShipStates { tick, ships } => {
            debug!("ship_states: tick={} count={}", tick, ships.len());
        }
        ServerMsg::MarketStates { tick, markets } => {
            debug!("market_states: tick={} count={}", tick, markets.len());
        }
        ServerMsg::FacilityStates { tick, facilities } => {
            debug!("facility_states: tick={} count={}", tick, facilities.len());
        }
        ServerMsg::PopulationStates { tick, populations } => {
            debug!("population_states: tick={} count={}", tick, populations.len());
        }
        ServerMsg::FactionStates { tick, factions } => {
            debug!("faction_states: tick={} count={}", tick, factions.len());
        }
        ServerMsg::ContractStates { tick, contracts } => {
            debug!("contract_states: tick={} count={}", tick, contracts.len());
        }
        ServerMsg::Events { tick, events } => {
            debug!("events: tick={} count={}", tick, events.len());
        }
        ServerMsg::AgentState { id, .. } => {
            debug!("agent_state: id={}", id);
        }
        ServerMsg::SimControlAck { action, tick, .. } => {
            info!("sim_control_ack: action={} tick={}", action, tick);
        }
    }
}

async fn run_net_loop(
    tx: Sender<ServerMsg>,
    mut out_rx: mpsc::UnboundedReceiver<String>,
) {
    loop {
        info!("connecting to {}", WS_URL);
        let connect_result = tokio_tungstenite::connect_async(WS_URL).await;
        let (ws_stream, _) = match connect_result {
            Ok(s) => {
                info!("connected");
                s
            }
            Err(e) => {
                warn!("connect failed: {e}, retrying in {:?}", RECONNECT_DELAY);
                tokio::time::sleep(RECONNECT_DELAY).await;
                continue;
            }
        };

        let (mut write, mut read) = ws_stream.split();

        // Send an initial hello so the server logs us. `ClientMsg::Hello`
        // serialisation would require a full ClientMsg Serialize impl;
        // at this bundle we cheat and send the raw JSON shape the server
        // expects. Bundle 2 will tighten this up.
        let hello =
            serde_json::json!({ "type": "hello", "client_id": "client-bevy" });
        if write.send(WsMessage::Text(hello.to_string())).await.is_err() {
            warn!("failed to send hello; will reconnect");
            continue;
        }

        loop {
            tokio::select! {
                frame = read.next() => {
                    match frame {
                        Some(Ok(WsMessage::Text(text))) => {
                            match serde_json::from_str::<ServerMsg>(&text) {
                                Ok(msg) => {
                                    if tx.send(msg).is_err() {
                                        warn!("Bevy side dropped NetInbox; exiting net loop");
                                        return;
                                    }
                                }
                                Err(e) => {
                                    warn!("parse error: {e} — text: {}", &text[..text.len().min(200)]);
                                }
                            }
                        }
                        Some(Ok(WsMessage::Binary(_))) => {
                            // Bundle 1 protocol is JSON text. Future MessagePack
                            // work would land here.
                            debug!("unexpected binary frame (ignored)");
                        }
                        Some(Ok(WsMessage::Close(c))) => {
                            info!("ws close: {:?}", c);
                            break;
                        }
                        Some(Ok(_)) => {} // ping/pong/etc.
                        Some(Err(e)) => {
                            warn!("ws read error: {e}");
                            break;
                        }
                        None => {
                            info!("ws stream ended");
                            break;
                        }
                    }
                }
                Some(out) = out_rx.recv() => {
                    if let Err(e) = write.send(WsMessage::Text(out)).await {
                        error!("ws write error: {e}");
                        break;
                    }
                }
            }
        }

        warn!("disconnected; reconnecting in {:?}", RECONNECT_DELAY);
        tokio::time::sleep(RECONNECT_DELAY).await;
    }
}
