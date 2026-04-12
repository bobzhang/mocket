///|
/// Error type for invalid native server configuration values.
pub suberror NativeServeError {
  InvalidMaxConnections(Int)
  InvalidMaxRequestBodyBytes(Int)
  InvalidRequestBodyReadTimeoutMs(Int)
  InvalidHandlerTimeoutMs(Int)
  InvalidShutdownTimeoutMs(Int)
  InvalidWebSocketMaxMessageBytes(Int)
  InvalidWebSocketOutgoingQueueCapacity(Int)
  InvalidWebSocketReadTimeoutMs(Int)
} derive(Debug, ToJson)

///|
/// Policy for handling a full outbound WebSocket message queue.
pub(all) enum NativeWebSocketOverflowPolicy {
  DropOldest
  DropLatest
} derive(Debug, Eq)

///|
pub impl Show for NativeWebSocketOverflowPolicy with output(self, logger) {
  match self {
    DropOldest => logger.write_string("DropOldest")
    DropLatest => logger.write_string("DropLatest")
  }
}

///|
/// Configuration options for the native async HTTP server runtime.
pub struct NativeServeOptions {
  max_connections : Int?
  max_request_body_bytes : Int?
  request_body_read_timeout_ms : Int?
  handler_timeout_ms : Int?
  shutdown_timeout_ms : Int?
  websocket_outgoing_queue_capacity : Int?
  websocket_overflow_policy : NativeWebSocketOverflowPolicy?
  websocket_read_timeout_ms : Int?
  websocket_max_message_bytes : Int?

  fn new(
    max_connections? : Int,
    max_request_body_bytes? : Int,
    request_body_read_timeout_ms? : Int,
    handler_timeout_ms? : Int,
    shutdown_timeout_ms? : Int,
    websocket_outgoing_queue_capacity? : Int,
    websocket_overflow_policy? : NativeWebSocketOverflowPolicy,
    websocket_read_timeout_ms? : Int,
    websocket_max_message_bytes? : Int,
  ) -> NativeServeOptions
}

///|
/// `max_connections`, if present, bounds concurrent accepted connections.
/// `max_request_body_bytes`, if present, rejects oversized request bodies
/// with `413 Request Entity Too Large`.
/// `request_body_read_timeout_ms`, if present, rejects slow request bodies
/// with `408 Request Timeout`.
/// `websocket_max_message_bytes`, if present, closes websocket connections
/// with `1009 MessageTooBig` when an inbound message exceeds that many bytes.
/// `websocket_outgoing_queue_capacity`, if present, bounds buffered outbound
/// websocket messages per connection.
/// `websocket_overflow_policy`, if present, chooses whether a full outbound
/// websocket queue drops the oldest or latest message.
/// `websocket_read_timeout_ms`, if present, closes websocket connections
/// after that many milliseconds waiting for the next inbound message.
pub fn NativeServeOptions::new(
  max_connections? : Int,
  max_request_body_bytes? : Int,
  request_body_read_timeout_ms? : Int,
  handler_timeout_ms? : Int,
  shutdown_timeout_ms? : Int,
  websocket_outgoing_queue_capacity? : Int,
  websocket_overflow_policy? : NativeWebSocketOverflowPolicy,
  websocket_read_timeout_ms? : Int,
  websocket_max_message_bytes? : Int,
) -> NativeServeOptions {
  {
    max_connections,
    max_request_body_bytes,
    request_body_read_timeout_ms,
    handler_timeout_ms,
    shutdown_timeout_ms,
    websocket_outgoing_queue_capacity,
    websocket_overflow_policy,
    websocket_read_timeout_ms,
    websocket_max_message_bytes,
  }
}

///|
fn resolve_native_max_connections(
  options : NativeServeOptions,
) -> Int? raise Error {
  match options.max_connections {
    Some(max_connections) => {
      guard max_connections > 0 else {
        raise NativeServeError::InvalidMaxConnections(max_connections)
      }
      Some(max_connections)
    }
    None => None
  }
}

///|
test "resolve_native_max_connections returns None when unset" {
  let result = resolve_native_max_connections(NativeServeOptions())
  inspect(result, content="None")
}

///|
test "resolve_native_max_connections accepts positive value" {
  let result = resolve_native_max_connections(
    NativeServeOptions(max_connections=5),
  )
  inspect(result, content="Some(5)")
}

///|
test "resolve_native_max_connections rejects zero" {
  let result : Result[Int?, Error] = try? resolve_native_max_connections(
    NativeServeOptions(max_connections=0),
  )
  inspect(result is Err(_), content="true")
}

///|
test "resolve_native_max_connections rejects negative" {
  let result : Result[Int?, Error] = try? resolve_native_max_connections(
    NativeServeOptions(max_connections=-1),
  )
  inspect(result is Err(_), content="true")
}

///|
fn resolve_native_max_request_body_bytes(
  options : NativeServeOptions,
) -> Int? raise Error {
  match options.max_request_body_bytes {
    Some(max_request_body_bytes) => {
      guard max_request_body_bytes >= 0 else {
        raise NativeServeError::InvalidMaxRequestBodyBytes(
          max_request_body_bytes,
        )
      }
      Some(max_request_body_bytes)
    }
    None => None
  }
}

///|
test "resolve_native_max_request_body_bytes returns None when unset" {
  let result = resolve_native_max_request_body_bytes(NativeServeOptions())
  inspect(result, content="None")
}

///|
test "resolve_native_max_request_body_bytes accepts zero" {
  let result = resolve_native_max_request_body_bytes(
    NativeServeOptions(max_request_body_bytes=0),
  )
  inspect(result, content="Some(0)")
}

///|
test "resolve_native_max_request_body_bytes accepts positive value" {
  let result = resolve_native_max_request_body_bytes(
    NativeServeOptions(max_request_body_bytes=1024),
  )
  inspect(result, content="Some(1024)")
}

///|
test "resolve_native_max_request_body_bytes rejects negative" {
  let result : Result[Int?, Error] = try? resolve_native_max_request_body_bytes(
    NativeServeOptions(max_request_body_bytes=-1),
  )
  inspect(result is Err(_), content="true")
}

///|
fn resolve_native_request_body_read_timeout_ms(
  options : NativeServeOptions,
) -> Int? raise Error {
  match options.request_body_read_timeout_ms {
    Some(request_body_read_timeout_ms) => {
      guard request_body_read_timeout_ms > 0 else {
        raise NativeServeError::InvalidRequestBodyReadTimeoutMs(
          request_body_read_timeout_ms,
        )
      }
      Some(request_body_read_timeout_ms)
    }
    None => None
  }
}

///|
test "resolve_native_request_body_read_timeout_ms returns None when unset" {
  let result = resolve_native_request_body_read_timeout_ms(NativeServeOptions())
  inspect(result, content="None")
}

///|
test "resolve_native_request_body_read_timeout_ms accepts positive value" {
  let result = resolve_native_request_body_read_timeout_ms(
    NativeServeOptions(request_body_read_timeout_ms=100),
  )
  inspect(result, content="Some(100)")
}

///|
test "resolve_native_request_body_read_timeout_ms rejects zero" {
  let result : Result[Int?, Error] = try? resolve_native_request_body_read_timeout_ms(
    NativeServeOptions(request_body_read_timeout_ms=0),
  )
  inspect(result is Err(_), content="true")
}

///|
test "resolve_native_request_body_read_timeout_ms rejects negative" {
  let result : Result[Int?, Error] = try? resolve_native_request_body_read_timeout_ms(
    NativeServeOptions(request_body_read_timeout_ms=-1),
  )
  inspect(result is Err(_), content="true")
}

///|
fn resolve_native_handler_timeout_ms(
  options : NativeServeOptions,
) -> Int? raise Error {
  match options.handler_timeout_ms {
    Some(handler_timeout_ms) => {
      guard handler_timeout_ms > 0 else {
        raise NativeServeError::InvalidHandlerTimeoutMs(handler_timeout_ms)
      }
      Some(handler_timeout_ms)
    }
    None => None
  }
}

///|
test "resolve_native_handler_timeout_ms returns None when unset" {
  let result = resolve_native_handler_timeout_ms(NativeServeOptions())
  inspect(result, content="None")
}

///|
test "resolve_native_handler_timeout_ms accepts positive value" {
  let result = resolve_native_handler_timeout_ms(
    NativeServeOptions(handler_timeout_ms=5000),
  )
  inspect(result, content="Some(5000)")
}

///|
test "resolve_native_handler_timeout_ms rejects zero" {
  let result : Result[Int?, Error] = try? resolve_native_handler_timeout_ms(
    NativeServeOptions(handler_timeout_ms=0),
  )
  inspect(result is Err(_), content="true")
}

///|
test "resolve_native_handler_timeout_ms rejects negative" {
  let result : Result[Int?, Error] = try? resolve_native_handler_timeout_ms(
    NativeServeOptions(handler_timeout_ms=-1),
  )
  inspect(result is Err(_), content="true")
}

///|
fn resolve_native_shutdown_timeout_ms(
  options : NativeServeOptions,
) -> Int? raise Error {
  match options.shutdown_timeout_ms {
    Some(shutdown_timeout_ms) => {
      guard shutdown_timeout_ms > 0 else {
        raise NativeServeError::InvalidShutdownTimeoutMs(shutdown_timeout_ms)
      }
      Some(shutdown_timeout_ms)
    }
    None => None
  }
}

///|
test "resolve_native_shutdown_timeout_ms returns None when unset" {
  let result = resolve_native_shutdown_timeout_ms(NativeServeOptions())
  inspect(result, content="None")
}

///|
test "resolve_native_shutdown_timeout_ms accepts positive value" {
  let result = resolve_native_shutdown_timeout_ms(
    NativeServeOptions(shutdown_timeout_ms=5000),
  )
  inspect(result, content="Some(5000)")
}

///|
test "resolve_native_shutdown_timeout_ms rejects zero" {
  let result : Result[Int?, Error] = try? resolve_native_shutdown_timeout_ms(
    NativeServeOptions(shutdown_timeout_ms=0),
  )
  inspect(result is Err(_), content="true")
}

///|
test "resolve_native_shutdown_timeout_ms rejects negative" {
  let result : Result[Int?, Error] = try? resolve_native_shutdown_timeout_ms(
    NativeServeOptions(shutdown_timeout_ms=-1),
  )
  inspect(result is Err(_), content="true")
}

///|
fn resolve_native_websocket_max_message_bytes(
  options : NativeServeOptions,
) -> Int? raise Error {
  match options.websocket_max_message_bytes {
    Some(websocket_max_message_bytes) => {
      guard websocket_max_message_bytes >= 0 else {
        raise NativeServeError::InvalidWebSocketMaxMessageBytes(
          websocket_max_message_bytes,
        )
      }
      Some(websocket_max_message_bytes)
    }
    None => None
  }
}

///|
test "resolve_native_websocket_max_message_bytes returns None when unset" {
  let result = resolve_native_websocket_max_message_bytes(NativeServeOptions())
  inspect(result, content="None")
}

///|
test "resolve_native_websocket_max_message_bytes accepts zero" {
  let result = resolve_native_websocket_max_message_bytes(
    NativeServeOptions(websocket_max_message_bytes=0),
  )
  inspect(result, content="Some(0)")
}

///|
test "resolve_native_websocket_max_message_bytes accepts positive value" {
  let result = resolve_native_websocket_max_message_bytes(
    NativeServeOptions(websocket_max_message_bytes=1024),
  )
  inspect(result, content="Some(1024)")
}

///|
test "resolve_native_websocket_max_message_bytes rejects negative" {
  let result : Result[Int?, Error] = try? resolve_native_websocket_max_message_bytes(
    NativeServeOptions(websocket_max_message_bytes=-1),
  )
  inspect(result is Err(_), content="true")
}

///|
fn resolve_native_websocket_outgoing_queue_capacity(
  options : NativeServeOptions,
) -> Int? raise Error {
  match options.websocket_outgoing_queue_capacity {
    Some(websocket_outgoing_queue_capacity) => {
      guard websocket_outgoing_queue_capacity > 0 else {
        raise NativeServeError::InvalidWebSocketOutgoingQueueCapacity(
          websocket_outgoing_queue_capacity,
        )
      }
      Some(websocket_outgoing_queue_capacity)
    }
    None => None
  }
}

///|
test "resolve_native_websocket_outgoing_queue_capacity returns None when unset" {
  let result = resolve_native_websocket_outgoing_queue_capacity(
    NativeServeOptions(),
  )
  inspect(result, content="None")
}

///|
test "resolve_native_websocket_outgoing_queue_capacity accepts positive value" {
  let result = resolve_native_websocket_outgoing_queue_capacity(
    NativeServeOptions(websocket_outgoing_queue_capacity=10),
  )
  inspect(result, content="Some(10)")
}

///|
test "resolve_native_websocket_outgoing_queue_capacity rejects zero" {
  let result : Result[Int?, Error] = try? resolve_native_websocket_outgoing_queue_capacity(
    NativeServeOptions(websocket_outgoing_queue_capacity=0),
  )
  inspect(result is Err(_), content="true")
}

///|
test "resolve_native_websocket_outgoing_queue_capacity rejects negative" {
  let result : Result[Int?, Error] = try? resolve_native_websocket_outgoing_queue_capacity(
    NativeServeOptions(websocket_outgoing_queue_capacity=-1),
  )
  inspect(result is Err(_), content="true")
}

///|
fn resolve_native_websocket_overflow_policy(
  options : NativeServeOptions,
) -> NativeWebSocketOverflowPolicy {
  match options.websocket_overflow_policy {
    Some(policy) =>
      match policy {
        DropOldest => DropOldest
        DropLatest => DropLatest
      }
    None => DropOldest
  }
}

///|
test "resolve_native_websocket_overflow_policy defaults to DropOldest" {
  let result = resolve_native_websocket_overflow_policy(NativeServeOptions())
  assert_eq(result, DropOldest)
}

///|
test "resolve_native_websocket_overflow_policy returns DropOldest" {
  let result = resolve_native_websocket_overflow_policy(
    NativeServeOptions(websocket_overflow_policy=DropOldest),
  )
  assert_eq(result, DropOldest)
}

///|
test "resolve_native_websocket_overflow_policy returns DropLatest" {
  let result = resolve_native_websocket_overflow_policy(
    NativeServeOptions(websocket_overflow_policy=DropLatest),
  )
  assert_eq(result, DropLatest)
}

///|
fn resolve_native_websocket_read_timeout_ms(
  options : NativeServeOptions,
) -> Int? raise Error {
  match options.websocket_read_timeout_ms {
    Some(websocket_read_timeout_ms) => {
      guard websocket_read_timeout_ms > 0 else {
        raise NativeServeError::InvalidWebSocketReadTimeoutMs(
          websocket_read_timeout_ms,
        )
      }
      Some(websocket_read_timeout_ms)
    }
    None => None
  }
}

///|
test "resolve_native_websocket_read_timeout_ms returns None when unset" {
  let result = resolve_native_websocket_read_timeout_ms(NativeServeOptions())
  inspect(result, content="None")
}

///|
test "resolve_native_websocket_read_timeout_ms accepts positive value" {
  let result = resolve_native_websocket_read_timeout_ms(
    NativeServeOptions(websocket_read_timeout_ms=100),
  )
  inspect(result, content="Some(100)")
}

///|
test "resolve_native_websocket_read_timeout_ms rejects zero" {
  let result : Result[Int?, Error] = try? resolve_native_websocket_read_timeout_ms(
    NativeServeOptions(websocket_read_timeout_ms=0),
  )
  inspect(result is Err(_), content="true")
}

///|
test "resolve_native_websocket_read_timeout_ms rejects negative" {
  let result : Result[Int?, Error] = try? resolve_native_websocket_read_timeout_ms(
    NativeServeOptions(websocket_read_timeout_ms=-1),
  )
  inspect(result is Err(_), content="true")
}
