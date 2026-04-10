///|
fn handle_not_found() -> HttpHandler {
  (_ : MocketEvent) => HttpResponse(status_code=NotFound).body("Not Found")
}
