# Server-Sent Events (SSE)

One-way server-to-client event streaming over plain HTTP. Unlike WebSocket,
SSE needs no upgrade handshake: the server sends `Content-Type:
text/event-stream` and keeps the response body open, pushing
newline-delimited events. Browsers consume it via the `EventSource` API and
reconnect automatically when the connection drops.

## How SSE Works

**1. Client opens a stream** — `EventSource("/events")` issues a GET request:

```
GET /events HTTP/1.1
Accept: text/event-stream
```

**2. Server responds and keeps the body open** — Crescent replies with the
event-stream headers and hands the handler an `SseEmitter`:

```
HTTP/1.1 200 OK
Content-Type: text/event-stream; charset=utf-8
Cache-Control: no-cache
Transfer-Encoding: chunked

data: hello

```

**3. Server pushes events** — each event is a set of `field: value` lines
terminated by a blank line:

```text
id: 42
event: update
data: first line
data: second line

```

`data` is the payload (`message` event by default), `event` names the event
type dispatched on the client, `id` sets the Last-Event-ID, and `retry`
advises the client how long to wait before reconnecting after a drop.

## Usage

Register an SSE route with `app.sse(path, handler)`. The handler receives an
`SseEmitter` and streams until it returns; the response is then terminated and
the connection closed (`EventSource` reconnects automatically).

```mbt check
///|
test "format an SSE event" {
  let event = SseEvent::SseEvent(data="update", id="1", event="update")
  debug_inspect(
    event.to_string(),
    content=(
      #|"id: 1\nevent: update\ndata: update\n\n"
    ),
  )
}
```

Dynamic routes work like HTTP routes, and captured params are available via
`emitter.param("name")`:

```moonbit nocheck
app.sse("/events/:room", emitter => {
  let room = emitter.param("room").unwrap_or("lobby")
  emitter.send_data("joined \{room}")
})
```

The handler also sees the full originating request via `emitter.request()`
(headers, query string, cookies) — this is how you resume after a client
reconnect by honoring `Last-Event-ID`:

```moonbit nocheck
app.sse("/events", emitter => {
  let resume_from = emitter.header("Last-Event-ID").unwrap_or("0")
  emitter.send_data("resuming from event \{resume_from}")
})
```

### API

| Item         | Purpose                                                                                                                                        |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `SseEvent`   | An event: `data` plus optional `id`, `event`, `retry`.                                                                                         |
| `SseEmitter` | The connected stream: `send`, `send_data`, `send_comment`, `close`, plus `param` (route params), `header`/`request` (the originating request). |
| `SseHandler` | Handler newtype wrapping `async (SseEmitter) -> Unit`.                                                                                         |

## Notes

- **Framing** — responses use chunked transfer encoding (no `Content-Length`),
  so events are delivered incrementally. Do not set `Content-Encoding` on a
  stream: the transport does not compress SSE responses.
- **Keep-alive** — `send_comment("...")` emits an `:` comment line, which
  `EventSource` ignores; use it as a ping through proxies that would
  otherwise time out an idle stream.
- **Middleware** — SSE endpoints are plain HTTP routes, so the request
  runs through the middleware chain before the stream starts: auth and
  rate-limit middleware can reject the stream with an ordinary response
  (e.g. `401`), and request-ID/security middleware contribute headers to
  the event-stream response.
- **Methods** — `app.sse` registers a `*` route: every HTTP verb invokes
  the handler (explicit `on`-registered routes at the same path keep
  precedence), on the live server and through `TestClient` alike. The
  route shows up in `routes()` as `("*", path)`.
- **Long-lived handlers** — the stream itself is not subject to the handler
  timeout: once the middleware chain completes, the handler owns the
  connection until it returns or the client disconnects.
- **Disconnects** — a client dropping mid-stream is noticed on the next
  write, which ends the handler and closes the connection. Like most
  streaming stacks (Django, Ktor), an _idle_ stream is not probed, so a
  handler that never writes cannot observe a dead client; periodic
  `send_comment` pings double as liveness checks.
- **Handler errors** — the status line is already on the wire, so a handler
  failure cannot become an HTTP error page: the body is terminated cleanly,
  the connection closed, and the error logged (`[crescent] sse handler
error: ...`). Cancellation during shutdown propagates normally.
