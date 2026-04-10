///|
async test "security_headers sets base headers by default" {
  let event = MocketEvent::{
    req: HttpRequest(Get, "/test", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let mw = security_headers()
  let handler : HttpHandler = fn(_event) noraise { "ok" }
  let middlewares : Array[(String, Middleware)] = [("", mw)]
  ignore(execute_middlewares(middlewares, event, handler))
  inspect(
    event.res.headers.get("X-Content-Type-Options"),
    content="Some(\"nosniff\")",
  )
  inspect(event.res.headers.get("X-Frame-Options"), content="Some(\"DENY\")")
  inspect(event.res.headers.get("X-XSS-Protection"), content="Some(\"0\")")
  inspect(
    event.res.headers.get("Referrer-Policy"),
    content="Some(\"strict-origin-when-cross-origin\")",
  )
  // Policy headers are opt-in, disabled by default
  inspect(event.res.headers.get("Strict-Transport-Security"), content="None")
  inspect(event.res.headers.get("Content-Security-Policy"), content="None")
  inspect(event.res.headers.get("Permissions-Policy"), content="None")
}

///|
async test "security_headers with opt-in policy headers" {
  let event = MocketEvent::{
    req: HttpRequest(Get, "/test", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let mw = security_headers(
    hsts="max-age=3600",
    csp="default-src 'self'; script-src 'self'",
    permissions_policy="camera=(), microphone=()",
  )
  let handler : HttpHandler = fn(_event) noraise { "ok" }
  let middlewares : Array[(String, Middleware)] = [("", mw)]
  ignore(execute_middlewares(middlewares, event, handler))
  inspect(
    event.res.headers.get("Strict-Transport-Security"),
    content="Some(\"max-age=3600\")",
  )
  inspect(
    event.res.headers.get("Content-Security-Policy"),
    content="Some(\"default-src 'self'; script-src 'self'\")",
  )
  inspect(
    event.res.headers.get("Permissions-Policy"),
    content="Some(\"camera=(), microphone=()\")",
  )
}

///|
async test "security_headers preserves handler-set headers" {
  let event = MocketEvent::{
    req: HttpRequest(Get, "/test", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  // Handler sets a custom CSP before middleware runs
  event.res.headers.set("Content-Security-Policy", "default-src 'none'")
  event.res.headers.set("X-Frame-Options", "SAMEORIGIN")
  let mw = security_headers(csp="default-src 'self'")
  let handler : HttpHandler = fn(_event) noraise { "ok" }
  let middlewares : Array[(String, Middleware)] = [("", mw)]
  ignore(execute_middlewares(middlewares, event, handler))
  // Per-route values must NOT be overwritten
  inspect(
    event.res.headers.get("Content-Security-Policy"),
    content="Some(\"default-src 'none'\")",
  )
  inspect(
    event.res.headers.get("X-Frame-Options"),
    content="Some(\"SAMEORIGIN\")",
  )
}

///|
async test "security_headers preserves handler response" {
  let event = MocketEvent::{
    req: HttpRequest(Get, "/hello", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let mw = security_headers()
  let handler : HttpHandler = fn(_event) noraise { "hello-response" }
  let middlewares : Array[(String, Middleware)] = [("", mw)]
  let result = execute_middlewares(middlewares, event, handler)
  let buf = @buffer.new()
  result.output(buf)
  inspect(@utf8.decode(buf.contents()), content="hello-response")
}
