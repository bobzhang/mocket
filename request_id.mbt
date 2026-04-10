///|
let request_id_counter : Ref[Int64] = Ref::new(0L)

///|
fn generate_request_id() -> String {
  let ts = @async.now()
  request_id_counter.val += 1L
  let counter = request_id_counter.val
  // Mix timestamp and counter to produce a non-sequential, opaque hex ID
  let mixed = ts.lxor(counter * 2654435761L)
  "\{mixed.to_string(radix=16)}-\{counter.to_string(radix=16)}"
}

///|
/// Returns a middleware that assigns a unique `X-Request-Id` header to every
/// request and response.
///
/// If the incoming request already carries an `X-Request-Id` header, its value
/// is preserved. Otherwise a new opaque hex identifier is generated.
pub fn request_id() -> Middleware {
  (event, next) => {
    let id = match event.req.get_header("X-Request-Id") {
      Some(existing) => existing
      None => generate_request_id()
    }
    // Set on request headers so handlers can access via event.request_id()
    event.req.headers.set("X-Request-Id", id)
    let res = next()
    // Set on response so clients can correlate
    event.res.headers.set("X-Request-Id", id)
    res
  }
}

///|
/// Returns the request ID for this event, or `None` if the middleware is not active.
pub fn MocketEvent::request_id(self : MocketEvent) -> String? {
  self.req.get_header("X-Request-Id")
}
