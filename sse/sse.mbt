///|
/// An SSE (Server-Sent Events) event: a `data` payload plus optional `id`,
/// `event`, and `retry` fields.
///
/// Serialized per the WHATWG SSE wire format — each field on its own line,
/// the event terminated by a blank line:
///
/// ```text
/// retry: 3000
/// id: 42
/// event: update
/// data: first line
/// data: second line
///
/// ```
pub(all) struct SseEvent {
  /// The event payload; embedded newlines are split into multiple `data:` lines.
  data : String
  /// Sets the Last-Event-ID seen by the client.
  id : String?
  /// The event type dispatched on the client; defaults to `"message"`.
  event : String?
  /// Reconnection time in milliseconds suggested to the client.
  retry : Int?
} derive(Eq, Debug)

///|
/// Creates an `SseEvent` with the given payload and optional attributes.
pub fn SseEvent::SseEvent(
  data~ : String,
  id? : String,
  event? : String,
  retry? : Int,
) -> SseEvent {
  { data, id, event, retry }
}

///|
/// Removes CR/LF from a single SSE field value so a value cannot inject
/// extra fields or break the framing.
fn sanitize_sse_field(s : String) -> String {
  if s.contains("\r") || s.contains("\n") {
    let buf = StringBuilder()
    for c in s {
      if c != '\r' && c != '\n' {
        buf.write_char(c)
      }
    }
    buf.to_string()
  } else {
    s
  }
}

///|
pub impl Show for SseEvent with fn output(self, logger) -> Unit {
  if self.retry is Some(retry) {
    logger.write_string("retry: ")
    logger.write_string(retry.to_string())
    logger.write_char('\n')
  }
  if self.id is Some(id) {
    logger.write_string("id: ")
    logger.write_string(sanitize_sse_field(id))
    logger.write_char('\n')
  }
  if self.event is Some(event) {
    logger.write_string("event: ")
    logger.write_string(sanitize_sse_field(event))
    logger.write_char('\n')
  }
  // The payload is split into one `data:` line per line, per the spec.
  for line in self.data.split("\n") {
    logger.write_string("data: ")
    logger.write_string(sanitize_sse_field(line.to_owned()))
    logger.write_char('\n')
  }
  // Blank line terminates the event.
  logger.write_char('\n')
}

///|
pub impl Show for SseEvent with fn to_string(self : SseEvent) -> String {
  let buf = StringBuilder()
  self.output(buf)
  buf.to_string()
}

///|
/// A connected Server-Sent Events emitter: the server-side handle on the
/// response stream handed to an SSE route handler, together with the
/// originating request (headers, query string, cookies) and the route
/// parameters captured from the request URL (e.g. `/events/:room`).
///
/// The stream stays open until the handler returns (the server then
/// terminates the response and closes the connection) or the remote client
/// disconnects. `EventSource` clients reconnect automatically.
pub struct SseEmitter {
  priv conn : @http.ServerConnection
  priv request : @core.HttpRequest
  priv params : Map[String, String]
  priv mut closed : Bool
}

///|
/// Wraps the response connection. `request` is the originating HTTP request
/// (only the live serving path provides it; defaults to an empty GET);
/// `params` are the route parameters captured from the SSE route URL.
pub fn SseEmitter::SseEmitter(
  conn : @http.ServerConnection,
  request? : @core.HttpRequest,
  params? : Map[String, String],
) -> SseEmitter {
  {
    conn,
    request: request.unwrap_or(
      @core.HttpRequest::from_method_string("GET", "", Map([]), b""),
    ),
    params: params.unwrap_or(Map([])),
    closed: false,
  }
}

///|
/// Returns the originating request, giving the handler access to headers,
/// the query string, and cookies. This is how SSE handlers read the
/// `Last-Event-ID` header when resuming after a client reconnect, or filter
/// per-client via query parameters.
pub fn SseEmitter::request(self : SseEmitter) -> @core.HttpRequest {
  self.request
}

///|
/// Returns a request header value (e.g. `Last-Event-ID`), or `None`.
pub fn SseEmitter::header(self : SseEmitter, name : String) -> String? {
  self.request.get_header(name)
}

///|
/// Returns a route parameter captured from the SSE route URL, or `None` if
/// the parameter was not present.
///
/// For example, a route `/events/:room` matched against `/events/lobby`
/// makes `emitter.param("room")` return `Some("lobby")`.
pub fn SseEmitter::param(self : SseEmitter, name : String) -> String? {
  self.params.get(name)
}

///|
/// Streams a single event and flushes the connection so the event is
/// delivered promptly. No-op after the emitter has closed.
pub async fn SseEmitter::send(self : SseEmitter, event : SseEvent) -> Unit {
  guard !self.closed else { return }
  self.conn.write_string(event.to_string())
  self.conn.flush()
}

///|
/// Streams a message event carrying only `data` to the remote client.
pub async fn SseEmitter::send_data(self : SseEmitter, data : String) -> Unit {
  self.send(SseEvent(data~))
}

///|
/// Streams a comment (`: ...`) to the remote client. Comments are ignored by
/// `EventSource` but are commonly used as keep-alive pings through proxies
/// that would otherwise time out an idle stream.
pub async fn SseEmitter::send_comment(
  self : SseEmitter,
  comment : String,
) -> Unit {
  guard !self.closed else { return }
  self.conn.write_string(": " + sanitize_sse_field(comment) + "\n\n")
  self.conn.flush()
}

///|
/// Ends the SSE response body. The server closes the underlying connection
/// after the handler returns; `close` is idempotent and safe to call early.
pub async fn SseEmitter::close(self : SseEmitter) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  self.conn.end_response() catch {
    _ => ()
  }
}

///|
/// Handler function type for SSE routes: receives the connected `SseEmitter`
/// and streams events until it returns, which ends the response.
pub(all) struct SseHandler(async (SseEmitter) -> Unit)
