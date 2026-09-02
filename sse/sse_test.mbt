///|
test "sse event with data only" {
  let event = SseEvent::SseEvent(data="hello")
  debug_inspect(
    event.to_string(),
    content=(
      #|"data: hello\n\n"
    ),
  )
}

///|
test "sse event with id, event type, and retry" {
  let event = SseEvent::SseEvent(
    data="world",
    id="42",
    event="update",
    retry=3000,
  )
  debug_inspect(
    event.to_string(),
    content=(
      #|"retry: 3000\nid: 42\nevent: update\ndata: world\n\n"
    ),
  )
}

///|
test "sse event splits multiline data into data lines" {
  let event = SseEvent::SseEvent(data="line1\nline2")
  debug_inspect(
    event.to_string(),
    content=(
      #|"data: line1\ndata: line2\n\n"
    ),
  )
}

///|
test "sse event with empty data still terminates" {
  let event = SseEvent::SseEvent(data="")
  debug_inspect(
    event.to_string(),
    content=(
      #|"data: \n\n"
    ),
  )
}

///|
test "sse event sanitizes newlines in id and event fields" {
  let event = SseEvent::SseEvent(
    data="x",
    id="1\r\ninjected: evil",
    event="a\nb",
  )
  debug_inspect(
    event.to_string(),
    content=(
      #|"id: 1injected: evil\nevent: ab\ndata: x\n\n"
    ),
  )
}

///|
test "sse event sanitizes carriage returns in data" {
  let event = SseEvent::SseEvent(data="a\r\nb")
  debug_inspect(
    event.to_string(),
    content=(
      #|"data: a\ndata: b\n\n"
    ),
  )
}
