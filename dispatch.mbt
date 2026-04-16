///|
/// Dispatches a synthetic HTTP request through the full routing + middleware
/// pipeline and returns `(status_code, headers, body_bytes)`.
pub async fn Mocket::dispatch(
  self : Mocket,
  http_method : String,
  url : String,
  headers : Map[String, String],
  body : Bytes,
) -> (StatusCode, Map[String, String], Bytes) {
  let request_path = @httputil.request_target_path(url)
  // Look up route
  let (params, handler) = match
    self.lookup_http_route(http_method, request_path) {
    Found(matched_handler, matched_params) => (matched_params, matched_handler)
    MethodNotAllowed(allow) => ({}, method_not_allowed_handler(allow))
    Options(allow) => ({}, options_handler(allow))
    NotFound =>
      match self.not_found_handler {
        Some(handler) => ({}, handler)
        None => ({}, handle_not_found())
      }
  }
  // Construct event
  let event = {
    req: HttpRequest::from_method_string(http_method, url, headers, body),
    res: HttpResponse(status_code=OK),
    params,
  }
  // Execute middleware chain + handler
  let responder = execute_middlewares(self.middlewares, event, handler)
  // Apply responder to response
  responder.options(event.res)
  match responder.output_bytes() {
    Some(bytes) => event.res.raw_body = bytes
    None => {
      let buf = @buffer.new()
      responder.output(buf)
      event.res.raw_body = buf.to_bytes()
    }
  }
  // Serialize cookies into Set-Cookie headers, matching the live server path
  // in send_response_async. Without this, TestClient silently drops cookies.
  append_cookie_headers(event.res.headers, event.res.cookies)
  // HEAD responses carry headers but no body bytes on the wire. Match the
  // live send_raw_response_async path: synthesize Content-Length from the
  // materialized body (unless the handler already set it), THEN drop the
  // body. TestClient callers can still assert on Content-Length.
  let body = if http_method == "HEAD" {
    if !@httputil.has_header_case_insensitive(event.res.headers, "Content-Length") {
      event.res.headers.set(
        "Content-Length", event.res.raw_body.length().to_string(),
      )
    }
    b""
  } else {
    event.res.raw_body
  }
  (event.res.status_code, event.res.headers, body)
}
