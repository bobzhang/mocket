///|
async test "security_headers sets base headers by default" {
  let app = @crescent.Mocket()
  app.use_middleware(security_headers())
  app.get("/test", _ => "ok")
  let client = @crescent.TestClient(app)
  let res = client.get("/test")
  inspect(
    res.headers.get("X-Content-Type-Options"),
    content="Some(\"nosniff\")",
  )
  inspect(res.headers.get("X-Frame-Options"), content="Some(\"DENY\")")
  inspect(res.headers.get("X-XSS-Protection"), content="Some(\"0\")")
  inspect(
    res.headers.get("Referrer-Policy"),
    content="Some(\"strict-origin-when-cross-origin\")",
  )
  // Policy headers are opt-in, disabled by default
  inspect(res.headers.get("Strict-Transport-Security"), content="None")
  inspect(res.headers.get("Content-Security-Policy"), content="None")
  inspect(res.headers.get("Permissions-Policy"), content="None")
}

///|
async test "security_headers with opt-in policy headers" {
  let app = @crescent.Mocket()
  app.use_middleware(
    security_headers(
      hsts="max-age=3600",
      csp="default-src 'self'; script-src 'self'",
      permissions_policy="camera=(), microphone=()",
    ),
  )
  app.get("/test", _ => "ok")
  let client = @crescent.TestClient(app)
  let res = client.get("/test")
  inspect(
    res.headers.get("Strict-Transport-Security"),
    content="Some(\"max-age=3600\")",
  )
  inspect(
    res.headers.get("Content-Security-Policy"),
    content="Some(\"default-src 'self'; script-src 'self'\")",
  )
  inspect(
    res.headers.get("Permissions-Policy"),
    content="Some(\"camera=(), microphone=()\")",
  )
}

///|
async test "security_headers preserves handler-set headers" {
  let app = @crescent.Mocket()
  // Middleware runs after the handler in onion order; we install it first,
  // then the handler sets custom headers inside the chain via `event.res`.
  app.use_middleware(security_headers(csp="default-src 'self'"))
  app.get("/test", event => {
    event.res.headers.set("Content-Security-Policy", "default-src 'none'")
    event.res.headers.set("X-Frame-Options", "SAMEORIGIN")
    "ok"
  })
  let client = @crescent.TestClient(app)
  let res = client.get("/test")
  // Per-route values must NOT be overwritten
  inspect(
    res.headers.get("Content-Security-Policy"),
    content="Some(\"default-src 'none'\")",
  )
  inspect(res.headers.get("X-Frame-Options"), content="Some(\"SAMEORIGIN\")")
}

///|
async test "security_headers preserves handler response" {
  let app = @crescent.Mocket()
  app.use_middleware(security_headers())
  app.get("/hello", _ => "hello-response")
  let client = @crescent.TestClient(app)
  let res = client.get("/hello")
  inspect(res.body_text(), content="hello-response")
}
