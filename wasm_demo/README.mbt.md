# bobzhang/crescent_wasm_demo

A minimal web server built with [Crescent](https://github.com/moonbit-community/crescent) that targets **wasm** as well as native (`supported_targets = "-all+native+wasm"`).

Routes:

- `GET /` — plain text greeting
- `GET /hello/:name` — path parameter echo
- `GET /json` — JSON response
- `GET /events` — Server-Sent Events stream (`text/event-stream`)

## Run

```sh
moon run wasm_demo/cmd/main --target wasm
moon run wasm_demo/cmd/main --target native
```

## Test

Handlers can be exercised without network I/O via `@crescent.test_client`:

```moonbit nocheck
///|
async test "hello route" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  let res = client.get("/hello/wasm")
  inspect(res.body_text(), content="Hello, wasm!")
}
```

SSE endpoints are dispatched synthetically too: the stream itself is not
replayable without a connection, so TestClient receives the event-stream
headers (`Content-Type: text/event-stream`) with an empty body:

```moonbit nocheck
///|
async test "events route" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  let res = client.get("/events")
  inspect(
    res.headers.get("Content-Type"),
    content=Some("text/event-stream; charset=utf-8"),
  )
}
```
