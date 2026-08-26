import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { WebEventStream, type AttachTransportHost } from "./web-event-stream"

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
    return () => {
      this.readyCallbacks.delete(callback)
    }
  }

  fireReady(): void {
    for (const callback of this.readyCallbacks) callback()
  }
}

beforeEach(() => {
  vi.useFakeTimers()
})

afterEach(() => {
  vi.useRealTimers()
})

describe("WebEventStream heartbeat", () => {
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
})
