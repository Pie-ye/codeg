# WebSocket Heartbeat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Codeg's web and remote-desktop event WebSockets active during idle periods by using the server's existing application-level ping/pong protocol.

**Architecture:** `WebEventStream` is the shared attach-protocol owner for both `WebTransport` and `RemoteDesktopTransport`. It will own one idempotent interval, send `{ action: "ping" }` only while the host reports an open socket, and clear the interval on destruction. Existing transport close/reconnect and attach/replay behavior remain unchanged.

**Tech Stack:** TypeScript, React transport layer, Vitest fake timers, Rust/Axum WebSocket integration tests, pnpm, Cargo.

## Global Constraints

- Use the existing `ClientMsg::Ping` / `ServerMsg::Pong` wire protocol; do not add a new message shape.
- Heartbeat interval is 20 seconds.
- Cover browser WebTransport and remote-desktop transport through `WebEventStream`'s shared `AttachTransportHost`.
- Do not clear tokens, redirect to login, or replace the existing exponential reconnect state machine on heartbeat send failure.
- Keep `/home/pieye/Container/codeg` deployment scripts untouched while changing `/home/pieye/Container/codeg-repo`.
- Follow TDD: add and run failing tests before the production implementation, then run focused and full verification.

---

### Task 1: Add failing heartbeat lifecycle tests

**Files:**
- Create: `src/lib/transport/web-event-stream.test.ts`
- Reference: `src/lib/transport/web-event-stream.ts`

**Interfaces:**
- Consumes the existing `AttachTransportHost` contract: `isWsOpen(): boolean`, `sendFrame(frame: object): boolean`, and `onWsReady(callback): () => void`.
- Produces executable expectations for the eventual `WebEventStream` timer: one ping per interval while open, no duplicate timer after repeated ready notifications, no ping while closed, and no ping after `destroy()`.

- [ ] **Step 1: Write the failing test**

Create a controllable host with an `open` flag, a `sent` array, and a set of ready callbacks. Use Vitest fake timers and assert the following behavior:

```ts
class TestHost implements AttachTransportHost {
  open: boolean
  sent: object[] = []
  private readyCallbacks = new Set<() => void>()

  constructor(open: boolean) {
    this.open = open
  }

  isWsOpen(): boolean {
    return this.open
  }

  sendFrame(frame: object): boolean {
    this.sent.push(frame)
    return true
  }

  onWsReady(callback: () => void): () => void {
    this.readyCallbacks.add(callback)
    return () => this.readyCallbacks.delete(callback)
  }

  fireReady(): void {
    for (const callback of this.readyCallbacks) callback()
  }
}

it("sends one application ping per interval while the socket is open", () => {
  const host = new TestHost(true)
  new WebEventStream(host)

  vi.advanceTimersByTime(20_000)

  expect(host.sent).toEqual([{ action: "ping" }])
})

it("does not create duplicate heartbeat timers across reconnects", () => {
  const host = new TestHost(true)
  new WebEventStream(host)
  host.fireReady()
  host.fireReady()

  vi.advanceTimersByTime(20_000)

  expect(host.sent).toHaveLength(1)
})

it("skips closed sockets and stops sending after destroy", () => {
  const host = new TestHost(true)
  const stream = new WebEventStream(host)
  host.open = false

  vi.advanceTimersByTime(20_000)
  expect(host.sent).toHaveLength(0)

  stream.destroy()
  host.open = true
  vi.advanceTimersByTime(40_000)
  expect(host.sent).toHaveLength(0)
})
```

The test host's `onWsReady` implementation must retain callbacks and return a disposer; `sendFrame` records the frame and returns `true`. Reset fake timers and globals in `beforeEach`/`afterEach`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
pnpm exec vitest run src/lib/transport/web-event-stream.test.ts
```

Expected: FAIL because `WebEventStream` currently does not schedule any heartbeat timer and `host.sent` remains empty.

- [ ] **Step 3: Commit the failing tests**

```bash
git add src/lib/transport/web-event-stream.test.ts
git commit -m "test: cover websocket heartbeat lifecycle"
```

### Task 2: Implement the shared heartbeat

**Files:**
- Modify: `src/lib/transport/web-event-stream.ts`
- Test: `src/lib/transport/web-event-stream.test.ts`

**Interfaces:**
- Consumes the existing `AttachTransportHost` without changing its public shape.
- Produces a private `heartbeatTimer` and `startHeartbeat()` lifecycle inside `WebEventStream`; no caller API changes.

- [ ] **Step 1: Write the minimal implementation**

Add a module constant and private timer:

```ts
const WS_HEARTBEAT_INTERVAL_MS = 20_000

private heartbeatTimer: ReturnType<typeof setInterval> | null = null
```

Start the timer from the existing ready callback and immediately when a stream is created over an already-open socket:

```ts
this.unbindWsReady = host.onWsReady(() => {
  this.startHeartbeat()
  this.reattachAll()
})
if (host.isWsOpen()) this.startHeartbeat()
```

Make `startHeartbeat()` idempotent and send only when the host is open:

```ts
private startHeartbeat(): void {
  if (this.heartbeatTimer !== null) return
  this.heartbeatTimer = setInterval(() => {
    if (this.host.isWsOpen()) {
      this.host.sendFrame({ action: "ping" })
    }
  }, WS_HEARTBEAT_INTERVAL_MS)
}
```

In `destroy()`, clear and null the timer before clearing subscriptions. Do not add reconnect state transitions or token handling to the heartbeat.

- [ ] **Step 2: Run focused tests to verify they pass**

Run:

```bash
pnpm exec vitest run src/lib/transport/web-event-stream.test.ts src/lib/transport/web-transport.test.ts
```

Expected: PASS, including the existing WebTransport reconnect tests.

- [ ] **Step 3: Run formatting/lint checks for changed TypeScript**

Run:

```bash
pnpm exec prettier --check src/lib/transport/web-event-stream.ts src/lib/transport/web-event-stream.test.ts
pnpm eslint src/lib/transport/web-event-stream.ts src/lib/transport/web-event-stream.test.ts
```

Expected: both commands exit 0.

- [ ] **Step 4: Commit the implementation**

```bash
git add src/lib/transport/web-event-stream.ts src/lib/transport/web-event-stream.test.ts
git commit -m "fix: keep event websocket alive with heartbeat"
```

### Task 3: Lock down the existing server ping/pong contract

**Files:**
- Modify: `src-tauri/tests/ws_attach.rs`
- Reference: `src-tauri/src/web/ws_attach.rs`, `src-tauri/src/web/ws.rs`

**Interfaces:**
- Consumes the existing authenticated `/ws/events` integration test server.
- Produces a regression test proving `{ "action": "ping" }` receives `{ "type": "pong" }`, which the TypeScript heartbeat relies on.

- [ ] **Step 1: Add the integration assertion**

Add an authenticated WebSocket test that drains the initial `__ready__` frame, sends JSON `{ "action": "ping" }`, receives the next JSON frame, and asserts `frame["type"] == "pong"`.

- [ ] **Step 2: Run the focused Rust integration test**

Run:

```bash
cargo test --test ws_attach --no-default-features ws_ping_receives_pong
```

Expected: PASS.

- [ ] **Step 3: Commit the protocol regression test**

```bash
git add src-tauri/tests/ws_attach.rs
git commit -m "test: verify websocket ping pong contract"
```

### Task 4: Full verification and safe deployment

**Files:**
- Verify: `src/lib/transport/web-event-stream.ts`
- Verify: `src/lib/transport/web-event-stream.test.ts`
- Verify: `src-tauri/tests/ws_attach.rs`
- Deployment target: `/usr/local/share/codeg/web` only after all checks pass

**Interfaces:**
- Consumes the tested source tree and existing native `codeg-server` service configuration.
- Produces a verified static build and an atomically staged web artifact; the backend process and data directory remain unchanged.

- [ ] **Step 1: Run the complete frontend checks**

Run:

```bash
pnpm test
pnpm eslint .
pnpm build
```

Expected: all commands exit 0 and `out/` contains a complete static export.

- [ ] **Step 2: Run the complete server checks relevant to this change**

Run from `src-tauri/`:

```bash
cargo test --no-default-features --bin codeg-server --lib
cargo test --test ws_attach --no-default-features
cargo check --no-default-features --bin codeg-server
```

Expected: all commands exit 0.

- [ ] **Step 3: Stage and smoke-test the built static artifact**

Use a unique staging directory and a timestamped backup, then atomically rename the old directory out of the way before installing the verified tree:

```bash
deploy_tmp="$(mktemp -d /tmp/codeg-web-heartbeat.XXXXXX)"
cp -a out/. "$deploy_tmp/"
test -f "$deploy_tmp/index.html"
test -d "$deploy_tmp/_next"
backup_dir="/usr/local/share/codeg/web.backup-$(date +%Y%m%d-%H%M%S)"
sudo mv /usr/local/share/codeg/web "$backup_dir"
sudo mv "$deploy_tmp" /usr/local/share/codeg/web
sudo systemctl --user restart codeg.service
```

If the restart or smoke test fails, restore the timestamped backup with
`sudo mv /usr/local/share/codeg/web "$failed_dir"` followed by
`sudo mv "$backup_dir" /usr/local/share/codeg/web` and restart the same
service. Do not alter `/home/pieye/.local/share/codeg` or
`/home/pieye/Container/codeg`.

- [ ] **Step 4: Verify the running service and public endpoint**

Confirm the service is active, `http://127.0.0.1:3080/` returns 200, and the public Codeg URL returns 200. Confirm the new built asset is served and the authenticated `/ws/events` endpoint still upgrades; do not print tokens or authorization headers.

- [ ] **Step 5: Review final diff and status**

Run:

```bash
git diff --check HEAD~2..HEAD
git status --short --branch
```

Expected: no whitespace errors and only intentional source/test changes plus the committed plan/spec documents remain.
