///|
/// The event passed to each HTTP handler, bundling the request, response, and route parameters.
pub(all) struct MocketEvent {
  req : HttpRequest
  res : HttpResponse
  params : Map[String, StringView]
}

///|
/// Parses the request body as JSON and deserializes into type `T`.
/// Shorthand for `event.req.json()`.
pub fn[T : @json.FromJson] MocketEvent::json(self : MocketEvent) -> T raise {
  self.req.json()
}

///|
/// Tries to parse the request body as JSON, returning `Ok(T)` on success
/// or `Err(message)` on failure. Shorthand for `event.req.try_json()`.
pub fn[T : @json.FromJson] MocketEvent::try_json(
  self : MocketEvent,
) -> Result[T, String] {
  self.req.try_json()
}

///|
/// Returns the request ID for this event, or `None` if the `request_id`
/// middleware from `bobzhang/crescent/middleware` is not active.
pub fn MocketEvent::request_id(self : MocketEvent) -> String? {
  self.req.get_header("X-Request-Id")
}
