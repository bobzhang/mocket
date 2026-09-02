///|
async fn main {
  let app = @crescent.App()

  // A clock: pushes a "tick" event every second, ten times, then ends.
  app.sse("/clock", emitter => {
    for i in 1..<=10 {
      emitter.send(SseEvent(data="tick \{i}", id=i.to_string(), event="tick"))
      @async.sleep(1000)
    }
  })

  // A per-room broadcast stub: params from the URL reach the handler.
  app.sse("/events/:room", emitter => {
    let room = emitter.param("room").unwrap_or("lobby")
    emitter.send_data("welcome to \{room}")
    emitter.send_comment("keepalive")
  })

  for path in app.routes() {
    println("\{path.0} http://localhost:3000\{path.1}")
  }

  app.serve(port=3000) catch {
    err => println("Server error: \{err}")
  }
}
