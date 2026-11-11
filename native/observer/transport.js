// Observer R2. Only HTTP and WebSocket I/O live here.
// Rendering, simulation state and decisions remain with the Observer.
export async function getJSON(path, request = fetch) {
  const response = await request(path, { cache: "no-store" });
  if (!response.ok) throw new Error("HTTP " + response.status + " " + path);
  return response.json();
}

export async function postJSON(path, value, request = fetch) {
  const response = await request(path, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify(value ?? {})
  });
  if (!response.ok) throw new Error("HTTP " + response.status + " " + path);
  return response.json();
}

// The caller retains socket identity and its existing 2500ms reconnect policy.
// No implicit retries of POST commands, and no simulation-side mutations.
export function openObserverSocket({
  url, onOpen, onMessage, onClose, onInvalidMessage, SocketType = WebSocket
}) {
  const socket = new SocketType(url);
  socket.addEventListener("open", () => onOpen?.());
  socket.addEventListener("message", event => {
    try {
      onMessage?.(JSON.parse(event.data));
    } catch (error) {
      onInvalidMessage?.(error);
    }
  });
  socket.addEventListener("close", () => onClose?.());
  socket.addEventListener("error", () => socket.close());
  return socket;
}
