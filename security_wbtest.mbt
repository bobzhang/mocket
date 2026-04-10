///|
async test "security_headers sets all expected headers" {
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
  inspect(
    event.res.headers.get("Strict-Transport-Security"),
    content="Some(\"max-age=63072000; includeSubDomains\")",
  )
  inspect(
    event.res.headers.get("Content-Security-Policy"),
    content="Some(\"default-src 'self'\")",
  )
  inspect(
    event.res.headers.get("Permissions-Policy"),
    content="Some(\"camera=(), microphone=(), geolocation=()\")",
  )
}

///|
async test "security_headers with custom values" {
  let event = MocketEvent::{
    req: HttpRequest(Get, "/test", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let mw = security_headers(
    hsts="max-age=3600",
    csp="default-src 'self'; script-src 'self'",
    permissions_policy="",
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
  // permissions_policy="" disables the header
  inspect(event.res.headers.get("Permissions-Policy"), content="None")
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
