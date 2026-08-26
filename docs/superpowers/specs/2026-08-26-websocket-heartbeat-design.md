# WebSocket heartbeat design

Date: 2026-08-26

## Problem

The web Codeg UI can report a lost connection and require a page refresh even
though the `codeg-server` process remains healthy. The browser event WebSocket
can be idle while it crosses a proxy such as Cloudflare. The server already
implements the attach protocol's application-level liveness exchange:

- client sends `{ "action": "ping" }`
- server replies with `{ "type": "pong" }`

The transports currently parse `pong` frames but never initiate this exchange.

## Goals

- Keep the WebSocket active during periods without ACP events.
- Use the existing protocol and avoid changing authentication or session state.
- Cover both browser WebTransport and remote-desktop transport through their
  shared `WebEventStream` host.
- Avoid duplicate timers across reconnects and release the timer on destroy.
- Preserve the existing reconnect and attach/replay behavior.

## Non-goals

- Changing Cloudflare or other proxy configuration.
- Replacing the existing exponential reconnect state machine.
- Treating a missing `pong` as an authentication failure.
- Adding a new server protocol or changing event payloads.

## Design

`WebEventStream` owns one heartbeat timer for the lifetime of the stream. The
timer is started when the transport reports a WebSocket-ready transition. If
the stream is created after the socket is already open, it starts immediately
when `isWsOpen()` reports true.

Every 20 seconds the timer checks `isWsOpen()` and, when open, sends:

```json
{"action":"ping"}
```

The existing `sendFrame` abstraction is used, so browser WebSocket and
Tauri's remote WebSocket proxy follow the same path. A failed send is ignored
by the heartbeat; the transport's existing close/reconnect lifecycle remains
authoritative. `pong` frames continue to be accepted and ignored by the event
stream because they are liveness acknowledgements, not application events.

The timer is idempotent: a reconnect callback reuses the existing timer rather
than creating another one. `destroy()` clears it before dropping subscriptions.

## Failure and lifecycle behavior

- Socket closed: heartbeat ticks see `isWsOpen() === false`; the existing
  reconnect path reattaches subscriptions when the socket is ready again.
- Socket open after reconnect: the same timer continues and no timer leak is
  introduced.
- `sendFrame` returns false or throws internally: no UI state change is made;
  existing transport state and reconnect handling decide recovery.
- Stream destroyed: no future heartbeat is sent.

This deliberately keeps heartbeat liveness separate from authentication. A
temporary network/proxy failure must not clear a valid token or redirect to
login.

## Testing

Add deterministic fake-timer coverage for:

1. one ping is sent after one heartbeat interval while the socket is open;
2. reconnect-ready callbacks do not create duplicate heartbeat sends;
3. closed sockets are not pinged;
4. destroy clears the timer;
5. the existing server integration path still accepts ping and returns pong.

Run the focused Vitest transport tests, the Rust WebSocket integration test,
the repository lint/test checks, and a production static build before any
deployment artifact is replaced.

## Deployment

The source of truth is `/home/pieye/Container/codeg-repo` with remote
`https://github.com/Pie-ye/codeg.git`. The existing deployment directory
`/home/pieye/Container/codeg` remains untouched until the source change is
verified and a build/deployment step is explicitly performed.
