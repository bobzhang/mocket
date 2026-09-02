///|
/// Builds the demo application: a few routes, an SSE stream, nothing else.
pub fn make_app() -> @crescent.App {
  let app = @crescent.App()
  app
  ..get("/", _ => "Hello from MoonBit on wasm!")
  ..get("/hello/:name", event => {
    let name = event.param("name").unwrap_or("World")
    "Hello, \{name}!"
  })
  ..get("/json", _ => ({ "framework": "crescent", "target": "wasm" } : Json))
  // A finite SSE stream: three events, then the handler returns and the
  // connection closes (`EventSource` reconnects automatically).
  .sse("/events", emitter => {
    emitter.send_data("connected")
    emitter.send(@crescent.SseEvent(data="tick 1", id="1", event="tick"))
    emitter.send_comment("keepalive")
  })
  app
}

///|
/// Serves the demo application on the given port.
pub async fn run(port~ : Int) -> Unit {
  make_app().serve(port~)
}
