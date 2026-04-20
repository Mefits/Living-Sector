//! WebSocket handler — one task per client connection.

use crate::{
    app_state::AppState,
    control::ControlCommand,
    ws::protocol::{ClientMsg, ServerMsg, SimControl},
};
use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    response::IntoResponse,
};
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use std::sync::atomic::Ordering;
use tokio::sync::broadcast::error::RecvError;
use tracing::{debug, info, warn};

pub async fn ws_upgrade(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: AppState) {
    let (mut sender, mut receiver) = socket.split();
    let mut broadcast_rx = state.broadcast_tx.subscribe();

    // Send initial hello
    let hello = ServerMsg::ServerHello {
        tick: state.tick.load(Ordering::Relaxed),
        running: state.running.load(Ordering::Relaxed),
        agent_count: state.agent_count.load(Ordering::Relaxed) as usize,
        interval_ms: state.interval_ms.load(Ordering::Relaxed),
    };
    if let Ok(text) = serde_json::to_string(&hello) {
        let _ = sender.send(Message::Text(text.into())).await;
    }
    info!("WS client connected");

    loop {
        tokio::select! {
            // Outbound — broadcast events
            event = broadcast_rx.recv() => {
                match event {
                    Ok(msg) => {
                        if let Ok(text) = serde_json::to_string(&*msg) {
                            if sender.send(Message::Text(text.into())).await.is_err() {
                                break;
                            }
                        }
                    }
                    Err(RecvError::Lagged(n)) => {
                        warn!("WS client lagged {n} messages — skipping");
                    }
                    Err(RecvError::Closed) => break,
                }
            }

            // Inbound — client commands
            msg = receiver.next() => {
                match msg {
                    Some(Ok(Message::Text(text))) => {
                        handle_client_msg(&text, &state, &mut sender).await;
                    }
                    Some(Ok(Message::Close(_))) | None => break,
                    Some(Err(e)) => {
                        debug!("WS receive error: {e}");
                        break;
                    }
                    _ => {}
                }
            }
        }
    }
    info!("WS client disconnected");
}

async fn handle_client_msg(
    text: &str,
    state: &AppState,
    sender: &mut futures_util::stream::SplitSink<WebSocket, Message>,
) {
    let parsed: Result<ClientMsg, _> = serde_json::from_str(text);
    let msg = match parsed {
        Ok(m) => m,
        Err(e) => {
            debug!("WS parse error: {e} on {text}");
            return;
        }
    };

    match msg {
        ClientMsg::Hello { client_id } => {
            debug!("WS hello from {:?}", client_id);
        }
        ClientMsg::GetAgent { id } => {
            let data = lookup_agent(state, &id);
            if let Some(data) = data {
                let reply = ServerMsg::AgentState { id, data };
                if let Ok(text) = serde_json::to_string(&reply) {
                    let _ = sender.send(Message::Text(text.into())).await;
                }
            }
        }
        ClientMsg::GetSnapshot { agent_type } => {
            let data = match agent_type.as_str() {
                "ships" => state.snapshots.ships.iter().map(|e| serde_json::to_value(e.value()).unwrap_or(json!(null))).collect(),
                "markets" => state.snapshots.markets.iter().map(|e| serde_json::to_value(e.value()).unwrap_or(json!(null))).collect(),
                "facilities" => state.snapshots.facilities.iter().map(|e| serde_json::to_value(e.value()).unwrap_or(json!(null))).collect(),
                "populations" => state.snapshots.populations.iter().map(|e| serde_json::to_value(e.value()).unwrap_or(json!(null))).collect(),
                "factions" => state.snapshots.factions.iter().map(|e| serde_json::to_value(e.value()).unwrap_or(json!(null))).collect(),
                "bodies" => state.snapshots.bodies.iter().map(|e| serde_json::to_value(e.value()).unwrap_or(json!(null))).collect(),
                _ => Vec::<serde_json::Value>::new(),
            };
            let reply = ServerMsg::AgentState {
                id: format!("snapshot-{}", agent_type),
                data: json!({ "kind": agent_type, "items": data }),
            };
            if let Ok(text) = serde_json::to_string(&reply) {
                let _ = sender.send(Message::Text(text.into())).await;
            }
        }
        ClientMsg::MoveObserver { id, x, y, radius } => {
            let _ = state
                .control_tx
                .send(ControlCommand::MoveObserver { id, x, y, radius })
                .await;
        }
        ClientMsg::SimControl(SimControl::Pause) => {
            let _ = state.control_tx.send(ControlCommand::Pause).await;
            send_ack(state, sender, "pause").await;
        }
        ClientMsg::SimControl(SimControl::Resume) => {
            let _ = state.control_tx.send(ControlCommand::Resume).await;
            send_ack(state, sender, "resume").await;
        }
        ClientMsg::SimControl(SimControl::SetTicksPerSecond { tps }) => {
            let _ = state
                .control_tx
                .send(ControlCommand::SetTicksPerSecond { tps })
                .await;
            send_ack(state, sender, "set_ticks_per_second").await;
        }
        ClientMsg::SimControl(SimControl::SetWorldSpeed { world_speed }) => {
            let _ = state
                .control_tx
                .send(ControlCommand::SetWorldSpeed { world_speed })
                .await;
            send_ack(state, sender, "set_world_speed").await;
        }
        ClientMsg::SimControl(SimControl::GetTick) => {
            let ack = ServerMsg::SimControlAck {
                action: "get_tick".into(),
                tick: state.tick.load(Ordering::Relaxed),
                running: state.running.load(Ordering::Relaxed),
            };
            if let Ok(text) = serde_json::to_string(&ack) {
                let _ = sender.send(Message::Text(text.into())).await;
            }
        }
    }
}

async fn send_ack(
    state: &AppState,
    sender: &mut futures_util::stream::SplitSink<WebSocket, Message>,
    action: &str,
) {
    let ack = ServerMsg::SimControlAck {
        action: action.into(),
        tick: state.tick.load(Ordering::Relaxed),
        running: state.running.load(Ordering::Relaxed),
    };
    if let Ok(text) = serde_json::to_string(&ack) {
        let _ = sender.send(Message::Text(text.into())).await;
    }
}

fn lookup_agent(state: &AppState, id: &str) -> Option<serde_json::Value> {
    if let Some(e) = state.snapshots.ships.get(id) {
        return serde_json::to_value(e.value()).ok();
    }
    if let Some(e) = state.snapshots.markets.get(id) {
        return serde_json::to_value(e.value()).ok();
    }
    if let Some(e) = state.snapshots.facilities.get(id) {
        return serde_json::to_value(e.value()).ok();
    }
    if let Some(e) = state.snapshots.populations.get(id) {
        return serde_json::to_value(e.value()).ok();
    }
    if let Some(e) = state.snapshots.factions.get(id) {
        return serde_json::to_value(e.value()).ok();
    }
    if let Some(e) = state.snapshots.bodies.get(id) {
        return serde_json::to_value(e.value()).ok();
    }
    None
}
