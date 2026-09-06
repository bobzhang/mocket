///|
let cached_date_second : Ref[Int64] = Ref(0L)

///|
let cached_date_string : Ref[String] = Ref("")

///|
fn current_http_date() -> String {
  let now = @async.now() / 1000L
  if now != cached_date_second.val {
    cached_date_second.val = now
    cached_date_string.val = @httputil.format_http_date(now)
  }
  cached_date_string.val
}

///|
fn append_cookie_headers(
  headers : Map[String, String],
  cookies : Map[String, @cookie.CookieItem],
) -> Unit {
  if cookies.is_empty() {
    return
  }
  let cookie_lines = cookies
    .values()
    .map(cookie => cookie.to_string())
    .to_array()
  match cookie_lines {
    [] => ()
    [cookie] => headers.set("Set-Cookie", cookie)
    _ => headers.set("Set-Cookie", cookie_lines.join("\r\nSet-Cookie: "))
  }
}

///|
/// `@http.Cookie` writes names and values verbatim, whereas Crescent's
/// `CookieItem` serialization removes delimiters that could inject another
/// cookie attribute or header. Preserve that invariant when adapting cookies
/// to the async HTTP transport.
fn sanitize_async_cookie_value(value : String) -> String {
  if value.contains("\r") || value.contains("\n") || value.contains(";") {
    let sanitized = StringBuilder()
    for char in value {
      if char != '\r' && char != '\n' && char != ';' {
        sanitized.write_char(char)
      }
    }
    sanitized.to_string()
  } else {
    value
  }
}

///|
/// Adapts Crescent's public cookie model to the async server's cookie channel,
/// which emits one `Set-Cookie` field per value instead of folding repeated
/// fields into a header map.
fn to_async_http_cookie(cookie : @cookie.CookieItem) -> @http.Cookie {
  let path = cookie.path
  let max_age = cookie.max_age.map(age => age.to_int64())
  let domain = cookie.domain
  let extensions = match cookie.same_site {
    Some(Lax) => ["SameSite=Lax"]
    Some(Strict) => ["SameSite=Strict"]
    Some(SameSiteNone) => ["SameSite=SameSiteNone"]
    None => []
  }
  Cookie(
    sanitize_async_cookie_value(cookie.name),
    sanitize_async_cookie_value(cookie.value),
    path?,
    max_age?,
    domain?,
    secure=cookie.secure.unwrap_or(false),
    http_only=cookie.http_only.unwrap_or(false),
    extensions~,
  )
}

///|
fn to_async_http_cookies(
  cookies : Map[String, @cookie.CookieItem],
) -> Array[@http.Cookie] {
  cookies.values().map(to_async_http_cookie).to_array()
}

///|
test "append_cookie_headers with empty cookies does nothing" {
  let headers : Map[String, String] = Map([])
  let cookies : Map[String, @cookie.CookieItem] = Map([])
  append_cookie_headers(headers, cookies)
  debug_inspect(headers.contains("Set-Cookie"), content="false")
}

///|
test "append_cookie_headers with single cookie sets header" {
  let headers : Map[String, String] = Map([])
  let cookies : Map[String, @cookie.CookieItem] = Map([])
  cookies.set("session", {
    name: "session",
    value: "abc123",
    max_age: None,
    path: None,
    domain: None,
    secure: None,
    http_only: None,
    same_site: None,
  })
  append_cookie_headers(headers, cookies)
  debug_inspect(
    headers.get("Set-Cookie"),
    content=(
      #|Some("session=abc123")
    ),
  )
}

///|
test "append_cookie_headers with multiple cookies joins with CRLF Set-Cookie" {
  let headers : Map[String, String] = Map([])
  let cookies : Map[String, @cookie.CookieItem] = Map([])
  cookies.set("a", {
    name: "a",
    value: "1",
    max_age: None,
    path: None,
    domain: None,
    secure: None,
    http_only: None,
    same_site: None,
  })
  cookies.set("b", {
    name: "b",
    value: "2",
    max_age: None,
    path: None,
    domain: None,
    secure: None,
    http_only: None,
    same_site: None,
  })
  append_cookie_headers(headers, cookies)
  debug_inspect(
    headers.get("Set-Cookie"),
    content=(
      #|Some("a=1\r\nSet-Cookie: b=2")
    ),
  )
}

///|
/// Applies the SSE protocol headers to a response.
fn apply_sse_headers(res : HttpResponse) -> Unit {
  @httputil.set_header_case_insensitive(
    res.headers,
    "Content-Type",
    "text/event-stream; charset=utf-8",
  )
  @httputil.set_header_case_insensitive(
    res.headers,
    "Cache-Control",
    "no-cache",
  )
  @httputil.set_header_case_insensitive(res.headers, "X-Accel-Buffering", "no")
}

///|
/// A marker responder for SSE routes. `options` applies the event-stream
/// headers, and the body is empty: a stream is not replayable, so synthetic
/// dispatch (TestClient) materializes a headers-only response, while the
/// live path uses the same responder as the signal that the middleware
/// chain reached the streaming endpoint. The payload is deliberately
/// empty — the `SseHandler` travels separately through the pipeline, never
/// inside this marker.
priv struct SseStreamResponder {}

///|
impl Responder for SseStreamResponder with fn options(_self, res) -> Unit {
  apply_sse_headers(res)
}

///|
impl Responder for SseStreamResponder with fn output(_self, _buf) -> Unit {

}

///|
impl Responder for SseStreamResponder with fn output_bytes(_self) -> Bytes? {
  None
}

///|
/// The synthetic HttpHandler for SSE routes: returns the `SseStreamResponder`
/// marker, so SSE requests flow through the ordinary middleware chain and
/// finalization like any other route (materializing the event-stream
/// headers with an empty body).
fn sse_synthetic_handler() -> HttpHandler {
  _event => SseStreamResponder::{ }
}

///|
/// Runs an SSE route on the live path: the request already went through the
/// ordinary route resolution, so `event` is the standard per-request event
/// (real body, headers, route params). The middleware chain runs first; a
/// middleware that short-circuits (e.g. auth rejecting the stream) returns
/// its own responder, which is then sent as an ordinary response. When the
/// chain completes, the request streams — no handler timeout applies to the
/// stream, and the connection is closed when it ends.
async fn handle_sse_request_async(
  request : @http.Request,
  conn : @http.ServerConnection,
  middlewares : Array[(String, Middleware)],
  event : Event,
  handler : @sse.SseHandler,
) -> Unit {
  let stream_requested : Ref[Bool] = Ref(false)
  let responder = execute_middlewares(middlewares, event, _event => {
    stream_requested.val = true
    SseStreamResponder::{ }
  })
  if stream_requested.val {
    stream_sse_response_async(conn, event, handler)
  } else {
    // A middleware short-circuited the chain: send its response normally.
    send_response_async(request, conn, event.res, responder)
  }
}

///|
async fn stream_sse_response_async(
  conn : @http.ServerConnection,
  event : Event,
  handler : @sse.SseHandler,
) -> Unit {
  apply_sse_headers(event.res)
  let headers = event.res.headers
  if !@httputil.has_header_case_insensitive(headers, "Date") {
    headers.set("Date", current_http_date())
  }
  // The connection is closed as soon as streaming ends and never reused:
  // advertise it so clients and proxies do not attempt keep-alive reuse.
  if !@httputil.has_header_case_insensitive(headers, "Connection") {
    headers.set("Connection", "close")
  }
  conn.send_response(
    event.res.status_code.to_int(),
    event.res.status_code.to_string(),
    extra_headers=headers,
    cookies=to_async_http_cookies(event.res.cookies),
  )
  // The emitter outlives the request buffer: params are copied to owned
  // Strings before streaming starts.
  let params : Map[String, String] = Map([])
  event.params.each((k, v) => params.set(k, v.to_owned()))
  let emitter = @sse.SseEmitter(conn, request=event.req, params~)
  // The response is already streaming, so a handler failure cannot become
  // an HTTP error page: the body is terminated and the connection closed
  // on every path. Cancellation propagates so task groups (graceful
  // shutdown) see it; other errors are logged rather than vanishing
  // silently.
  let mut handler_error : Error? = None
  handler(emitter) catch {
    err => handler_error = Some(err)
  }
  emitter.close()
  conn.close()
  match handler_error {
    Some(err) if @async.is_cancellation_error(err) => raise err
    Some(err) => println("[crescent] sse handler error: \{err}")
    None => ()
  }
}

///|
async fn send_raw_response_async(
  conn : @http.ServerConnection,
  response : HttpResponse,
  headers : Map[String, String],
  include_body : Bool,
) -> Unit {
  append_cookie_headers(headers, response.cookies)
  if !@httputil.has_header_case_insensitive(headers, "Date") {
    headers.set("Date", current_http_date())
  }
  if !@httputil.has_header_case_insensitive(headers, "Content-Length") {
    headers.set("Content-Length", response.raw_body.length().to_string())
  }
  if !@httputil.has_header_case_insensitive(headers, "Connection") {
    headers.set("Connection", "close")
  }
  let raw_response = Buffer()
  raw_response.write_string_utf8("HTTP/1.1 ")
  raw_response.write_string_utf8(response.status_code.to_int().to_string())
  raw_response.write_string_utf8(" ")
  raw_response.write_string_utf8(response.status_code.to_string())
  raw_response.write_string_utf8("\r\n")
  for pair in headers.to_array() {
    let (key, value) = pair
    raw_response.write_string_utf8(key)
    raw_response.write_string_utf8(": ")
    raw_response.write_string_utf8(value)
    raw_response.write_string_utf8("\r\n")
  }
  raw_response.write_string_utf8("\r\n")
  if include_body && !response.raw_body.is_empty() {
    raw_response.write_bytes(response.raw_body)
  }
  conn.enter_passthrough_mode()
  conn.write(raw_response.contents())
  conn.flush()
  conn.close()
}

///|
/// Applies a responder and materializes its body. Shared by the live serving
/// path (`send_response_async`) and synthetic dispatch (`App::dispatch`) so
/// responder options and bytes stay aligned (see commits bb22108, eb6f24b).
/// Cookie serialization stays at the transport boundary: live responses use
/// async's typed cookie API, while raw and synthetic responses need headers.
fn finalize_response_body(
  response : HttpResponse,
  responder : &Responder,
) -> Unit {
  responder.options(response)
  // Fast path: use output_bytes to avoid buffer allocation when possible
  match responder.output_bytes() {
    Some(bytes) => response.raw_body = bytes
    None => {
      let buffer = Buffer()
      responder.output(buffer)
      response.raw_body = buffer.to_bytes()
    }
  }
}

///|
async fn send_response_async(
  request : @http.Request,
  conn : @http.ServerConnection,
  response : HttpResponse,
  responder : &Responder,
) -> Unit {
  finalize_response_body(response, responder)
  let headers = response.headers
  if !@httputil.has_header_case_insensitive(headers, "Date") {
    headers.set("Date", current_http_date())
  }
  if request.meth == Head {
    send_raw_response_async(conn, response, headers, false)
    return
  }
  if @httputil.has_header_case_insensitive(headers, "Content-Encoding") {
    send_raw_response_async(conn, response, headers, true)
    return
  }
  conn.send_response(
    response.status_code.to_int(),
    response.status_code.to_string(),
    extra_headers=headers,
    cookies=to_async_http_cookies(response.cookies),
  )
  if !response.raw_body.is_empty() {
    conn.write(response.raw_body)
  }
  conn.end_response()
}

///|
async fn send_response_and_close_async(
  request : @http.Request,
  conn : @http.ServerConnection,
  response : HttpResponse,
) -> Unit {
  let headers = response.headers
  if !@httputil.has_header_case_insensitive(headers, "Date") {
    headers.set("Date", current_http_date())
  }
  if !@httputil.has_header_case_insensitive(headers, "Content-Length") {
    headers.set("Content-Length", response.raw_body.length().to_string())
  }
  headers.set("Connection", "close")
  if request.meth == Head {
    send_raw_response_async(conn, response, headers, false)
    return
  }
  conn.send_response(
    response.status_code.to_int(),
    response.status_code.to_string(),
    extra_headers=headers,
    cookies=to_async_http_cookies(response.cookies),
  )
  if !response.raw_body.is_empty() {
    conn.write(response.raw_body)
  }
  conn.end_response()
  conn.close()
}

///|
async fn send_request_entity_too_large_async(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let response = HttpResponse(status_code=RequestEntityTooLarge).body(
    "Request Entity Too Large",
  )
  response.headers.set("Content-Type", "text/plain; charset=utf-8")
  send_response_and_close_async(request, conn, response)
}

///|
async fn send_request_timeout_async(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let response = HttpResponse(status_code=RequestTimeout).body(
    "Request Timeout",
  )
  response.headers.set("Content-Type", "text/plain; charset=utf-8")
  send_response_and_close_async(request, conn, response)
}

///|
async fn send_not_found_async(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let response = HttpResponse(status_code=NotFound).body("Not Found")
  response.headers.set("Content-Type", "text/plain; charset=utf-8")
  send_response_and_close_async(request, conn, response)
}

///|
async fn send_gateway_timeout_async(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let response = HttpResponse(status_code=GatewayTimeout).body(
    "Gateway Timeout",
  )
  response.headers.set("Content-Type", "text/plain; charset=utf-8")
  send_response_and_close_async(request, conn, response)
}
