import assert from "node:assert/strict";
import test from "node:test";
import {getJSON,postJSON,openObserverSocket} from "./transport.js";

test("GET preserves no-store HTTP semantics and error reporting", async () => {
  const calls = [];
  const request = async (path, options) => {
    calls.push({path,options});
    return {ok:true,json:async()=>({tick:42})};
  };
  assert.deepEqual(await getJSON("/api/report",request),{tick:42});
  assert.deepEqual(calls,[{path:"/api/report",options:{cache:"no-store"}}]);
  await assert.rejects(getJSON("/api/report",async()=>({ok:false,status:503})),/HTTP 503 \/api\/report/);
});

test("POST keeps explicit JSON body and does not retry failed commands", async () => {
  const calls=[];
  const request=async(path,options)=>{calls.push({path,options});return {ok:true,json:async()=>({accepted:true})};};
  assert.deepEqual(await postJSON("/api/sim/speed",{world_speed:16},request),{accepted:true});
  assert.deepEqual(calls,[{path:"/api/sim/speed",options:{
    method:"POST",headers:{"Content-Type":"application/json"},body:'{"world_speed":16}'
  }}]);
  let attempts=0;
  await assert.rejects(postJSON("/api/sim/pause",{},async()=>{attempts++;return {ok:false,status:409};}),/HTTP 409/);
  assert.equal(attempts,1);
});

test("WebSocket forwards parsed messages, errors, and close without UI state", () => {
  class FakeSocket {
    constructor(url){this.url=url;this.listeners=new Map();this.closeCount=0;}
    addEventListener(name,fn){this.listeners.set(name,fn);}
    emit(name,data){this.listeners.get(name)?.(data);}
    close(){this.closeCount++;}
  }
  const events=[],messages=[],invalid=[];
  const socket=openObserverSocket({
    url:"ws://example.test/ws",SocketType:FakeSocket,
    onOpen:()=>events.push("open"),
    onMessage:m=>messages.push(m),
    onClose:()=>events.push("close"),
    onInvalidMessage:e=>invalid.push(e.message)
  });
  assert.equal(socket.url,"ws://example.test/ws");
  socket.emit("open");
  socket.emit("message",{data:'{"type":"events","tick":4}'});
  socket.emit("message",{data:"{bad json"});
  socket.emit("close");
  socket.emit("error");
  assert.deepEqual(events,["open","close"]);
  assert.deepEqual(messages,[{type:"events",tick:4}]);
  assert.equal(invalid.length,1);
  assert.equal(socket.closeCount,1);
});
