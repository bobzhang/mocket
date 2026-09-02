///|
async test "GET /" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  let res = client.get("/")
  inspect(
    res.status,
    content=(
      #|OK
    ),
  )
  inspect(res.body_text(), content="Hello from MoonBit on wasm!")
}

///|
async test "GET /hello/:name" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  let res = client.get("/hello/wasm")
  inspect(
    res.status,
    content=(
      #|OK
    ),
  )
  inspect(res.body_text(), content="Hello, wasm!")
}

///|
async test "GET /hello without name falls back to World" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  let res = client.get("/hello/")
  inspect(
    res.body_text(),
    content=(
      #|Hello, !
    ),
  )
}

///|
async test "GET /json" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  let res = client.get("/json")
  inspect(
    res.status,
    content=(
      #|OK
    ),
  )
  inspect(
    res.body_text(),
    content=(
      #|{"framework":"crescent","target":"wasm"}
    ),
  )
}

///|
async test "GET /events is a server-sent events endpoint" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  let res = client.get("/events")
  inspect(
    res.status,
    content=(
      #|OK
    ),
  )
  inspect(
    res.headers.get("Content-Type").unwrap_or(""),
    content="text/event-stream; charset=utf-8",
  )
  inspect(res.headers.get("Cache-Control").unwrap_or(""), content="no-cache")
  inspect(res.body_text(), content="")
}

///|
async test "GET /events/:id does not exist" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  let res = client.get("/events/extra")
  inspect(
    res.status,
    content=(
      #|NotFound
    ),
  )
}

///|
async test "POST /events reaches the SSE route" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  // SSE routes match any method; a stream is not replayable, so the
  // synthetic client materializes the event-stream headers with an empty
  // body.
  let res = client.post("/events", body=b"")
  inspect(
    res.status,
    content=(
      #|OK
    ),
  )
  inspect(
    res.headers.get("Content-Type").unwrap_or(""),
    content="text/event-stream; charset=utf-8",
  )
  inspect(res.body_text(), content="")
}
