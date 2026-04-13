///|
async fn main {
  let app = @crescent.Mocket()
  // Use get_raw to avoid the error-wrapping overhead on the hot path.
  // These handlers never raise, so automatic error mapping is pure cost.
  app.get_raw("/text", _ => "Hello, World!")
  app.get_raw("/json", _ => ({ "message": "Hello, World!" } : Json))
  app.get_raw("/user/:id", event => {
    let id = event.param("id").unwrap_or("0")
    ({ "id": id, "name": "User \{id}" } : Json)
  })
  println("Mocket server listening on port 3001")
  app.serve(port=3001) catch {
    err => println("Server error: \{err}")
  }
}
